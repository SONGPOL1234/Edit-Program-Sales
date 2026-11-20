/* =====================================================================
   Quotation Calibration (หน้าสร้าง/แก้ใบเสนอราคา) - ส่วนเพิ่มต่อจาก Quotation_List.sql
   SQL Server 2016 SP1 ขึ้นไป · รันหลัง Recall_System.sql และ Quotation_List.sql
   ---------------------------------------------------------------------
   แนวคิด
   1) หัวใบ (Qt_Quotation) + รายการ (Qt_QuotationItem) เดิม  เพิ่มฟิลด์ตามหน้าจอ Cover Letter / Calculation Items
   2) สถานะ / PO / Forecast / Invoice เก็บ "รายบรรทัด" เหมือนแท็บ Status เดิม  รับ PO บางรายการได้
      สถานะของใบคำนวณจากบรรทัดอัตโนมัติ (sp_Qt_SyncHeaderStatus)
   3) QN Type = Recall : เลือกเครื่องที่ครบกำหนดของลูกค้า แล้วเติม Description + Cal. ID / Manuf / Model / Serial / ราคาครั้งก่อน / Quote By
   4) Revision : เก็บฉบับก่อนหน้าไว้ทั้งชุด (Qt_QuotationRevision) ก่อนแก้ราคา
   5) Cost Details : คำนวณต้นทุนและ GP% ต่อใบ (v_Qt_Margin)
   หมายเหตุ: ถ้าระบบจริงมีตารางใบเสนอราคาอยู่แล้ว ให้ส่งชื่อตาราง/คอลัมน์มา จะเปลี่ยนให้ ALTER ตารางเดิมแทน
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   1) หัวใบ : ฟิลด์ตามแท็บ Cover Letter
   --------------------------------------------------------------------- */
IF COL_LENGTH('dbo.Qt_Quotation','Revision') IS NULL
ALTER TABLE dbo.Qt_Quotation ADD
    Revision        INT            NOT NULL CONSTRAINT DF_Qt_Rev DEFAULT 0,
    CustomerReqNo   NVARCHAR(30)   NULL,                                        -- Customer Request No. (CN0005/26)
    Branch          NVARCHAR(50)   NULL,
    Sender          NVARCHAR(100)  NULL,
    ApprovedBy      NVARCHAR(100)  NULL,
    IsReference     BIT            NOT NULL CONSTRAINT DF_Qt_IsRef DEFAULT 0,   -- QN Type: Reference
    RefQNNo         NVARCHAR(30)   NULL,                                        -- QN ที่อ้างอิง/คัดลอกมา
    FeeType         NVARCHAR(30)   NULL,                                        -- Calibration Fee / Repair Fee / Rental Fee / Training Fee / Product Sale
    Project         NVARCHAR(255)  NULL,
    PriceValidity   NVARCHAR(30)   NULL,
    DeliveryTime    NVARCHAR(30)   NULL,
    DeliverTo       NVARCHAR(255)  NULL,
    CustomerRef     NVARCHAR(255)  NULL,                                        -- Reference ของลูกค้า
    CreditTerm      VARCHAR(12)    NULL CHECK (CreditTerm IN ('CASH','CREDIT','POST_CHEQUE')),
    TermOfPayment   NVARCHAR(50)   NULL,
    DiscountPerItem BIT            NOT NULL CONSTRAINT DF_Qt_Dpi DEFAULT 1,
    SpecialDiscount DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Qt_SpDisc DEFAULT 0,
    CustomerReqFile NVARCHAR(500)  NULL,                                        -- ไฟล์ Customer Request ที่แนบ
    POFile          NVARCHAR(500)  NULL,
    RemarkReport    NVARCHAR(2000) NULL,
    NoteInItem      NVARCHAR(2000) NULL,
    CustAddress     NVARCHAR(500)  NULL,                                        -- ที่อยู่ลูกค้าบนใบเสนอราคา
    CustTel         NVARCHAR(100)  NULL,
    CustEmail       NVARCHAR(150)  NULL;
GO

/* ข้อความสำเร็จรูปของช่อง "Used in note" */
IF OBJECT_ID('dbo.Qt_NoteTemplate') IS NULL
BEGIN
    CREATE TABLE dbo.Qt_NoteTemplate (NoteID INT IDENTITY PRIMARY KEY, Title NVARCHAR(100) NOT NULL, NoteText NVARCHAR(1000) NOT NULL, IsActive BIT NOT NULL DEFAULT 1);
    INSERT dbo.Qt_NoteTemplate (Title, NoteText) VALUES
      (N'ใช้ใบรับรองเดิม', N'- Refer to Last year Certificate'),
      (N'17025',           N'- All Item with Accreditation 17025'),
      (N'เงื่อนไขสอบเทียบ', N'- Calibration Condition;-'),
      (N'On-site',         N'- On-site calibration at customer site, customer provides power supply and working area');
END;
GO

/* ---------------------------------------------------------------------
   2) รายการ : ฟิลด์ตามแท็บ Calculation Items + สถานะรายบรรทัด (แท็บ Status)
   --------------------------------------------------------------------- */
IF COL_LENGTH('dbo.Qt_QuotationItem','Qty') IS NULL
ALTER TABLE dbo.Qt_QuotationItem ADD
    Manufacturer    NVARCHAR(100)  NULL,
    Model           NVARCHAR(100)  NULL,
    Qty             DECIMAL(18,2)  NOT NULL CONSTRAINT DF_QtI_Qty DEFAULT 1,
    DiscountPct     DECIMAL(5,2)   NOT NULL CONSTRAINT DF_QtI_Disc DEFAULT 0,
    LastPrice       DECIMAL(18,2)  NULL,                       -- ราคาครั้งก่อน (เตือนเมื่อเสนอต่ำกว่า)
    TISI            VARCHAR(10)    NULL,
    ANAB            VARCHAR(10)    NULL,
    ItemType        NVARCHAR(30)   NULL,
    CertType        NVARCHAR(20)   NULL,
    LineStatus      VARCHAR(10)    NOT NULL CONSTRAINT DF_QtI_St DEFAULT 'SUBMIT'
                    CONSTRAINT CK_QtI_St CHECK (LineStatus IN ('SUBMIT','PO','JOB','INV','LOST','CANCEL')),
    PONo            NVARCHAR(50)   NULL,
    PODate          DATE           NULL,
    ForecastDate    DATE           NULL,                       -- คาดว่าจะได้ PO (ใช้ทำยอดคาดการณ์)
    InvoiceNo       NVARCHAR(30)   NULL,
    InvoiceDate     DATE           NULL,
    LostReasonCode  VARCHAR(20)    NULL CONSTRAINT FK_QtI_Lost REFERENCES dbo.Rc_CancelReason(ReasonCode),
    LineUpdatedAt   DATETIME2(0)   NULL;
GO
IF COL_LENGTH('dbo.Qt_QuotationItem','LineTotal') IS NULL
    ALTER TABLE dbo.Qt_QuotationItem ADD LineTotal AS ROUND(UnitPrice * Qty * (1 - DiscountPct / 100), 2) PERSISTED;
GO

/* สถานะหัวใบเพิ่ม 2 ค่า */
IF NOT EXISTS (SELECT 1 FROM dbo.Qt_Status WHERE QStatus = 'PARTIAL_PO')
    INSERT dbo.Qt_Status VALUES ('PARTIAL_PO', N'ได้ PO บางรายการ', 3, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.Qt_Status WHERE QStatus = 'INVOICED')
    INSERT dbo.Qt_Status VALUES ('INVOICED', N'ออก Invoice ครบ', 5, 0);
GO

/* ---------------------------------------------------------------------
   3) สถานะหัวใบ คำนวณจากบรรทัด
      ทุกบรรทัด CANCEL -> CANCELLED · ไม่เหลือบรรทัดที่ยังมีผล -> LOST
      บรรทัดที่เหลือ INV ทั้งหมด -> INVOICED · JOB/INV ทั้งหมด -> JOB_RECEIVED
      ไม่มี SUBMIT เหลือ -> PO_RECEIVED · มีบางบรรทัดได้ PO -> PARTIAL_PO · อื่น ๆ -> WAIT_PO (หรือ DRAFT ถ้ายังไม่ส่ง)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_SyncHeaderStatus @QNNo NVARCHAR(30), @UserName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @old VARCHAR(12), @new VARCHAR(12), @n INT, @cancel INT, @live INT, @inv INT, @job INT, @sub INT;
    SELECT @old = QStatus FROM dbo.Qt_Quotation WHERE QNNo = @QNNo;
    SELECT @n = COUNT(*),
           @cancel = SUM(CASE WHEN LineStatus = 'CANCEL' THEN 1 ELSE 0 END),
           @live   = SUM(CASE WHEN LineStatus NOT IN ('LOST','CANCEL') THEN 1 ELSE 0 END),
           @inv    = SUM(CASE WHEN LineStatus = 'INV' THEN 1 ELSE 0 END),
           @job    = SUM(CASE WHEN LineStatus IN ('JOB','INV') THEN 1 ELSE 0 END),
           @sub    = SUM(CASE WHEN LineStatus = 'SUBMIT' THEN 1 ELSE 0 END)
    FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo;

    SET @new = CASE WHEN @n = 0 THEN @old
                    WHEN @cancel = @n THEN 'CANCELLED'
                    WHEN @live = 0 THEN 'LOST'
                    WHEN @inv = @live THEN 'INVOICED'
                    WHEN @job = @live THEN 'JOB_RECEIVED'
                    WHEN @sub = 0 THEN 'PO_RECEIVED'
                    WHEN @sub < @live THEN 'PARTIAL_PO'
                    WHEN @old = 'DRAFT' THEN 'DRAFT'
                    ELSE 'WAIT_PO' END;

    IF @new <> @old
    BEGIN
        UPDATE q SET QStatus = @new,
               PONo = COALESCE(q.PONo, (SELECT TOP 1 PONo FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo AND PONo IS NOT NULL ORDER BY PODate)),
               PODate = COALESCE(q.PODate, (SELECT MIN(PODate) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo)),
               OrderReceived = (SELECT SUM(LineTotal) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo AND LineStatus IN ('PO','JOB','INV')),
               InvoiceDate = (SELECT MAX(InvoiceDate) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo),
               LostReasonCode = CASE WHEN @new = 'LOST' THEN (SELECT TOP 1 LostReasonCode FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo AND LostReasonCode IS NOT NULL GROUP BY LostReasonCode ORDER BY COUNT(*) DESC) ELSE q.LostReasonCode END,
               UpdatedAt = SYSDATETIME(), UpdatedBy = @UserName
        FROM dbo.Qt_Quotation q WHERE q.QNNo = @QNNo;
        INSERT dbo.Qt_StatusHist (QNNo, FromStatus, ToStatus, Note, ChangedBy) VALUES (@QNNo, @old, @new, N'คำนวณจากสถานะรายบรรทัด', @UserName);
    END;
END;
GO

/* ปุ่ม Update ในแท็บ Status : อัปเดตหลายบรรทัดพร้อมกัน
   @LineNums = '1,2,5' หรือ NULL = ทุกบรรทัด (All Rows) */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_UpdateLines
    @QNNo NVARCHAR(30), @LineNums NVARCHAR(MAX) = NULL, @LineStatus VARCHAR(10),
    @PONo NVARCHAR(50) = NULL, @PODate DATE = NULL, @ForecastDate DATE = NULL,
    @InvoiceNo NVARCHAR(30) = NULL, @InvoiceDate DATE = NULL, @ReceiveNo NVARCHAR(30) = NULL,
    @ReasonCode VARCHAR(20) = NULL, @UserName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @LineStatus = 'PO'  AND @PONo IS NULL      THROW 50201, N'สถานะ ได้ PO ต้องใส่ PO No.', 1;
    IF @LineStatus = 'JOB' AND @ReceiveNo IS NULL THROW 50202, N'สถานะ รับเครื่อง ต้องใส่ RN', 1;
    IF @LineStatus = 'INV' AND @InvoiceNo IS NULL THROW 50203, N'สถานะ ออก Invoice ต้องใส่ Inv. No.', 1;
    IF @LineStatus = 'LOST' AND NOT EXISTS (SELECT 1 FROM dbo.Rc_CancelReason WHERE ReasonCode = @ReasonCode)
        THROW 50204, N'กรุณาเลือกเหตุผลที่ไม่ได้งาน', 1;

    BEGIN TRAN;
    UPDATE i SET LineStatus = @LineStatus,
        PONo = ISNULL(@PONo, i.PONo), PODate = CASE WHEN @PONo IS NOT NULL THEN ISNULL(@PODate, CAST(GETDATE() AS DATE)) ELSE i.PODate END,
        ForecastDate = ISNULL(@ForecastDate, i.ForecastDate),
        InvoiceNo = ISNULL(@InvoiceNo, i.InvoiceNo), InvoiceDate = CASE WHEN @InvoiceNo IS NOT NULL THEN ISNULL(@InvoiceDate, CAST(GETDATE() AS DATE)) ELSE i.InvoiceDate END,
        NewReceiveNo = ISNULL(@ReceiveNo, i.NewReceiveNo),
        LostReasonCode = CASE WHEN @LineStatus = 'LOST' THEN @ReasonCode ELSE i.LostReasonCode END,
        LineUpdatedAt = SYSDATETIME()
    FROM dbo.Qt_QuotationItem i
    WHERE i.QNNo = @QNNo AND (@LineNums IS NULL OR i.LineNum IN (SELECT TRY_CONVERT(INT, value) FROM STRING_SPLIT(@LineNums, ',')));

    IF @ReceiveNo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Qt_QuotationRN WHERE QNNo = @QNNo AND ReceiveNo = @ReceiveNo)
        INSERT dbo.Qt_QuotationRN (QNNo, ReceiveNo, RecDate) VALUES (@QNNo, @ReceiveNo, CAST(GETDATE() AS DATE));

    /* sync งาน Recall ของบรรทัดที่ผูกกับเครื่อง */
    UPDATE t SET RecallStatus = CASE @LineStatus WHEN 'PO' THEN 'ACCEPTED' WHEN 'JOB' THEN 'SCHEDULED' WHEN 'INV' THEN t.RecallStatus
                                     ELSE CASE WHEN cr.StopRecall = 1 THEN 'CANCELLED' WHEN t.DueDate < CAST(GETDATE() AS DATE) THEN 'OVERDUE' ELSE 'OPEN' END END,
                 NewQNNo = CASE WHEN @LineStatus IN ('LOST','CANCEL') THEN NULL ELSE @QNNo END, UpdatedAt = SYSDATETIME()
    FROM dbo.Rc_RecallTask t
    JOIN dbo.Qt_QuotationItem i ON i.RecallID = t.RecallID AND i.QNNo = @QNNo
    LEFT JOIN dbo.Rc_CancelReason cr ON cr.ReasonCode = @ReasonCode
    WHERE t.RecallStatus NOT IN ('RECEIVED','CANCELLED')
      AND (@LineNums IS NULL OR i.LineNum IN (SELECT TRY_CONVERT(INT, value) FROM STRING_SPLIT(@LineNums, ',')));

    EXEC dbo.sp_Qt_SyncHeaderStatus @QNNo = @QNNo, @UserName = @UserName;
    COMMIT;
END;
GO

/* ---------------------------------------------------------------------
   4) QN Type = Recall : รายการเครื่องให้เลือก + เพิ่มเข้าใบที่เปิดอยู่
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_RecallCandidates @CustomerID NVARCHAR(20), @DaysBack INT = 180, @DaysAhead INT = 120
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.RecallID, l.CalID, l.Description, l.Manuf, l.Model, l.SerialNo, l.DueDate, l.DaysToDue, l.RecallStatus,
           l.LastReceiveNo, l.LastQNNo, l.SaleName, LastPrice = l.ItemPrice,
           InQNNo = (SELECT TOP 1 qi.QNNo FROM dbo.Qt_QuotationItem qi JOIN dbo.Qt_Quotation q ON q.QNNo = qi.QNNo
                     WHERE qi.RecallID = l.RecallID AND q.QStatus NOT IN ('LOST','CANCELLED'))
    FROM dbo.v_Rc_RecallList l
    WHERE l.CustomerID = @CustomerID AND l.RecallStatus NOT IN ('RECEIVED','CANCELLED')
      AND l.DaysToDue BETWEEN -@DaysBack AND @DaysAhead
    ORDER BY l.DueDate, l.CalID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Qt_AddRecallLines @QNNo NVARCHAR(30), @RecallIDs NVARCHAR(MAX), @UserName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @start INT = ISNULL((SELECT MAX(LineNum) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo), 0);
    BEGIN TRAN;
    INSERT dbo.Qt_QuotationItem (QNNo, LineNum, EquipmentID, RecallID, CalID, Description, Manufacturer, Model, SerialNo,
                                 OldReceiveNo, OldQNNo, DueDate, UnitPrice, LastPrice, Qty, TISI, ANAB, CertType)
    SELECT @QNNo, @start + ROW_NUMBER() OVER (ORDER BY l.DueDate, l.CalID), l.EquipmentID, l.RecallID, l.CalID,
           l.Description + N'  ' + l.CalID, l.Manuf, l.Model, l.SerialNo, l.LastReceiveNo, l.LastQNNo, l.DueDate,
           l.ItemPrice, l.ItemPrice, 1, 'Not', 'ANAB', 'Not'
    FROM dbo.v_Rc_RecallList l
    JOIN STRING_SPLIT(@RecallIDs, ',') s ON TRY_CONVERT(INT, s.value) = l.RecallID
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Qt_QuotationItem qi JOIN dbo.Qt_Quotation q ON q.QNNo = qi.QNNo
                      WHERE qi.RecallID = l.RecallID AND q.QStatus NOT IN ('LOST','CANCELLED'));

    /* Quote By = Sale ที่ดูแลเครื่องมากที่สุด (ถ้ายังว่าง), ติ๊ก QN Type Recall */
    UPDATE q SET SourceType = 'R',
        ControlBy = ISNULL(q.ControlBy, (SELECT TOP 1 l.SaleName FROM dbo.v_Rc_RecallList l JOIN STRING_SPLIT(@RecallIDs, ',') s ON TRY_CONVERT(INT, s.value) = l.RecallID
                                         WHERE l.SaleName IS NOT NULL GROUP BY l.SaleName ORDER BY COUNT(*) DESC)),
        QuoPrice = (SELECT SUM(LineTotal) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo) - q.SpecialDiscount,
        UpdatedBy = @UserName, UpdatedAt = SYSDATETIME()
    FROM dbo.Qt_Quotation q WHERE q.QNNo = @QNNo;

    UPDATE t SET NewQNNo = @QNNo, UpdatedAt = SYSDATETIME()
    FROM dbo.Rc_RecallTask t JOIN STRING_SPLIT(@RecallIDs, ',') s ON TRY_CONVERT(INT, s.value) = t.RecallID;
    COMMIT;
END;
GO

/* รายการ Description มาตรฐาน + ราคาล่าสุด (ส่วนล่างของแท็บ Calculation Items) */
CREATE OR ALTER VIEW dbo.v_Qt_DescriptionCatalog
AS
SELECT Description = d.Description, d.Manufacturer, d.Model, LastPrice = d.UnitPrice, UsedCount = d.cnt, LastUsed = d.LastUsed
FROM (
    SELECT i.Description, i.Manufacturer, i.Model, i.UnitPrice, q.CreatedAt AS LastUsed,
           cnt = COUNT(*) OVER (PARTITION BY i.Description, i.Manufacturer, i.Model),
           rn  = ROW_NUMBER() OVER (PARTITION BY i.Description, i.Manufacturer, i.Model ORDER BY q.CreatedAt DESC)
    FROM dbo.Qt_QuotationItem i JOIN dbo.Qt_Quotation q ON q.QNNo = i.QNNo
    WHERE i.UnitPrice > 0 AND i.RecallID IS NULL       -- ไม่เอา Cal. ID ที่ต่อท้าย Description ของงาน Recall
) d WHERE d.rn = 1;
GO

/* ---------------------------------------------------------------------
   5) Revision / Copy
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_QuotationRevision') IS NULL
CREATE TABLE dbo.Qt_QuotationRevision (
    QNNo        NVARCHAR(30) NOT NULL REFERENCES dbo.Qt_Quotation(QNNo),
    Revision    INT          NOT NULL,
    QuoPrice    DECIMAL(18,2) NOT NULL,
    HeaderJson  NVARCHAR(MAX) NOT NULL,     -- ภาพหัวใบ ณ ตอนนั้น (FOR JSON)
    LinesJson   NVARCHAR(MAX) NOT NULL,     -- ภาพรายการ ณ ตอนนั้น
    CreatedBy   NVARCHAR(100) NULL,
    CreatedAt   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Qt_QuotationRevision PRIMARY KEY (QNNo, Revision)
);
GO
CREATE OR ALTER PROCEDURE dbo.sp_Qt_NewRevision @QNNo NVARCHAR(30), @UserName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    INSERT dbo.Qt_QuotationRevision (QNNo, Revision, QuoPrice, HeaderJson, LinesJson, CreatedBy)
    SELECT q.QNNo, q.Revision, q.QuoPrice,
           (SELECT q2.* FROM dbo.Qt_Quotation q2 WHERE q2.QNNo = q.QNNo FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT i.* FROM dbo.Qt_QuotationItem i WHERE i.QNNo = q.QNNo ORDER BY i.LineNum FOR JSON PATH),
           @UserName
    FROM dbo.Qt_Quotation q WITH (UPDLOCK) WHERE q.QNNo = @QNNo;
    UPDATE dbo.Qt_Quotation SET Revision = Revision + 1, UpdatedBy = @UserName, UpdatedAt = SYSDATETIME() WHERE QNNo = @QNNo;
    INSERT dbo.Qt_StatusHist (QNNo, FromStatus, ToStatus, Note, ChangedBy)
    SELECT QNNo, QStatus, QStatus, N'ออก Revision ' + CONVERT(NVARCHAR(5), Revision), @UserName FROM dbo.Qt_Quotation WHERE QNNo = @QNNo;
    COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_Qt_CopyQuotation @FromQNNo NVARCHAR(30), @NewQNNo NVARCHAR(30) = NULL OUTPUT, @UserName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    EXEC dbo.sp_Qt_NextNo @QNNo = @NewQNNo OUTPUT;
    INSERT dbo.Qt_Quotation (QNNo, CustomerID, CustomerName, InquiryDate, DueDate, QuotationType, Subject, QuoPrice, CurrencyCode, ControlBy,
                             ContactName, ContactTel, QStatus, SourceType, Remarks, CreatedBy, UpdatedBy,
                             Branch, Sender, ApprovedBy, IsReference, RefQNNo, FeeType, Project, PriceValidity, DeliveryTime, DeliverTo,
                             CreditTerm, TermOfPayment, DiscountPerItem, SpecialDiscount, NoteInItem)
    SELECT @NewQNNo, CustomerID, CustomerName, CAST(GETDATE() AS DATE), DATEADD(DAY, 30, CAST(GETDATE() AS DATE)), QuotationType, Subject, QuoPrice, CurrencyCode, ControlBy,
           ContactName, ContactTel, 'DRAFT', 'M', NULL, @UserName, @UserName,
           Branch, Sender, ApprovedBy, 1, @FromQNNo, FeeType, Project, PriceValidity, DeliveryTime, DeliverTo,
           CreditTerm, TermOfPayment, DiscountPerItem, SpecialDiscount, NoteInItem
    FROM dbo.Qt_Quotation WHERE QNNo = @FromQNNo;
    INSERT dbo.Qt_QuotationItem (QNNo, LineNum, CalID, Description, Manufacturer, Model, SerialNo, UnitPrice, LastPrice, Qty, DiscountPct, TISI, ANAB, ItemType, CertType)
    SELECT @NewQNNo, LineNum, CalID, Description, Manufacturer, Model, SerialNo, UnitPrice, UnitPrice, Qty, DiscountPct, TISI, ANAB, ItemType, CertType
    FROM dbo.Qt_QuotationItem WHERE QNNo = @FromQNNo;           -- ไม่คัดลอก RecallID / สถานะ / PO
    INSERT dbo.Qt_StatusHist (QNNo, ToStatus, Note, ChangedBy) VALUES (@NewQNNo, 'DRAFT', N'คัดลอกจาก ' + @FromQNNo, @UserName);
    COMMIT;
END;
GO

/* ---------------------------------------------------------------------
   6) Cost Details + กำไร
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_CostDetail') IS NULL
CREATE TABLE dbo.Qt_CostDetail (
    QNNo          NVARCHAR(30)  NOT NULL PRIMARY KEY REFERENCES dbo.Qt_Quotation(QNNo),
    OnSiteDate    DATE NULL, OnSiteArea NVARCHAR(255) NULL,
    EngCostPerDay DECIMAL(18,2) NOT NULL DEFAULT 0, EngStaff  INT NOT NULL DEFAULT 0,
    LeadCostPerDay DECIMAL(18,2) NOT NULL DEFAULT 0, LeadStaff INT NOT NULL DEFAULT 0,
    OilPerKm      DECIMAL(18,2) NOT NULL DEFAULT 0, Km INT NOT NULL DEFAULT 0,
    Transport     NVARCHAR(255) NULL, TransCostPerTrip DECIMAL(18,2) NOT NULL DEFAULT 0, Trips INT NOT NULL DEFAULT 0,
    Hotel         NVARCHAR(255) NULL, HotelCostPerNight DECIMAL(18,2) NOT NULL DEFAULT 0, Rooms INT NOT NULL DEFAULT 0,
    ComPct        DECIMAL(5,2)  NOT NULL DEFAULT 0, SubContract DECIMAL(18,2) NOT NULL DEFAULT 0, OthersCal DECIMAL(18,2) NOT NULL DEFAULT 0,
    RemarkCal     NVARCHAR(1000) NULL,
    ProdCost      DECIMAL(18,2) NOT NULL DEFAULT 0, ProdComPct DECIMAL(5,2) NOT NULL DEFAULT 0, ProdTaxVat DECIMAL(18,2) NOT NULL DEFAULT 0, ProdOthers DECIMAL(18,2) NOT NULL DEFAULT 0,
    RemarkProd    NVARCHAR(1000) NULL
);
GO
CREATE OR ALTER VIEW dbo.v_Qt_Margin
AS
SELECT q.QNNo, q.CustomerName, q.ControlBy, q.QStatus, NetSales = q.QuoPrice,
       CalCost  = c.EngCostPerDay*c.EngStaff + c.LeadCostPerDay*c.LeadStaff + c.OilPerKm*c.Km + c.TransCostPerTrip*c.Trips
                + c.HotelCostPerNight*c.Rooms + q.QuoPrice*c.ComPct/100 + c.SubContract + c.OthersCal,
       ProdCost = c.ProdCost + q.QuoPrice*c.ProdComPct/100 + c.ProdTaxVat + c.ProdOthers
FROM dbo.Qt_Quotation q JOIN dbo.Qt_CostDetail c ON c.QNNo = q.QNNo;
GO
CREATE OR ALTER VIEW dbo.v_Qt_MarginPct
AS
SELECT m.*, TotalCost = m.CalCost + m.ProdCost, GP = m.NetSales - (m.CalCost + m.ProdCost),
       GPPct = CAST(100.0 * (m.NetSales - (m.CalCost + m.ProdCost)) / NULLIF(m.NetSales, 0) AS DECIMAL(6,1)),
       BelowTarget = CASE WHEN 100.0 * (m.NetSales - (m.CalCost + m.ProdCost)) / NULLIF(m.NetSales, 0) < 30 THEN 1 ELSE 0 END   -- เป้า GP 30%
FROM dbo.v_Qt_Margin m;
GO

/* ---------------------------------------------------------------------
   7) ยอดคาดการณ์จาก Forecast (ต่อเข้า Sales Dashboard)
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.v_Qt_Forecast
AS
SELECT q.ControlBy, ForecastMonth = FORMAT(i.ForecastDate, 'yyyy-MM'), q.QNNo, q.CustomerName,
       LineCount = COUNT(*), ForecastValue = SUM(i.LineTotal)
FROM dbo.Qt_QuotationItem i JOIN dbo.Qt_Quotation q ON q.QNNo = i.QNNo
WHERE i.LineStatus = 'SUBMIT' AND i.ForecastDate IS NOT NULL
GROUP BY q.ControlBy, FORMAT(i.ForecastDate, 'yyyy-MM'), q.QNNo, q.CustomerName;
GO

/* ---------------------------------------------------------------------
   9) แบบฟอร์มใบเสนอราคาของบริษัท (FORM 404-05/JUN,21)
      ตามตัวอย่าง QN00008/26 : หัวกระดาษ PCal + ilac-MRA/ANAB, กล่องลูกค้า/เลขที่,
      รายการทีละเครื่อง (Cert. 17025 ANAB / SUB, Qty, Unit Price, Discount %, Amount),
      ตัวอักษรบาท, Sub Total / VAT / Total, เงื่อนไข 5 ข้อ, Approved By
   --------------------------------------------------------------------- */
IF COL_LENGTH('dbo.Qt_FormSetting','TelText') IS NULL
ALTER TABLE dbo.Qt_FormSetting ADD
    TelText       NVARCHAR(100)  NULL,
    IntroText     NVARCHAR(500)  NULL,
    POMailText    NVARCHAR(500)  NULL,
    ChequeText    NVARCHAR(500)  NULL,
    ApproverName  NVARCHAR(100)  NULL,
    AccreditLogo  VARBINARY(MAX) NULL,
    FormNo        NVARCHAR(30)   NULL;
GO
UPDATE dbo.Qt_FormSetting SET
    CompanyNameTh = N'บริษัท โปรเฟสชั่นแนล แคริเบรชั่น แอนด์ เซอร์วิสเซส จำกัด',
    CompanyNameEn = N'Professional Calibration & Services Co., Ltd.',
    AddressText   = N'50/888,50/889 หมู่ 2 ถ.รังสิต-นครนายก ต.บึงยี่โถ อ.ธัญบุรี จ.ปทุมธานี 12130',
    TelText       = N'Tel : 02-150-6641 ( Autoline )',
    TaxID         = '0135546001177',
    IntroText     = N'บริษัทฯ มีความยินดีขอเสนอราคา และเงื่อนไขการให้บริการสอบเทียบมาตรฐานเครื่องมือวัดตามรายการต่อไปนี้ :',
    POMailText    = N'เมื่อได้รับใบเสนอราคานี้แล้ว หากอนุมัติการดำเนินการ กรุณาส่งใบสั่งซื้อ (PO) มาที่อีเมล์ Info@p-cal.com และ CC: pcal@p-cal.com',
    ChequeText    = N'โปรดสั่งจ่ายเช็คในนาม "บริษัท โปรเฟสชั่นแนล แคริเบรชั่น แอนด์ เซอร์วิสเซส จำกัด" และขีดหรือผู้ถือออก',
    ApproverName  = N'Mr.Manote Piwnimnual',
    ApproverTitle = N'Laboratory Manager',
    FormNo        = N'FORM 404-05/JUN,21'
WHERE SettingID = 1;
GO

/* เบอร์มือถือของ Sale ที่แสดงในช่อง Sales Contact / Mobile No. */
IF OBJECT_ID('dbo.Qt_SaleProfile') IS NULL
    CREATE TABLE dbo.Qt_SaleProfile (SaleName NVARCHAR(100) NOT NULL PRIMARY KEY, MobileNo NVARCHAR(30) NULL, Email NVARCHAR(150) NULL);
GO

/* ข้อมูลพิมพ์ตามแบบฟอร์ม: 3 result sets (1) หัวใบ+ยอดรวม (2) รายการทีละบรรทัด (3) ตั้งค่าแบบฟอร์ม */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_PrintForm @QNNo NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @vat DECIMAL(5,2) = (SELECT VatRate FROM dbo.Qt_FormSetting WHERE SettingID = 1);
    DECLARE @sub DECIMAL(18,2) = (SELECT SUM(LineTotal) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo AND LineStatus <> 'CANCEL');

    SELECT q.QNNo, q.Revision, QuotationDate = ISNULL(q.SubmitDate, CAST(q.CreatedAt AS DATE)), q.CustomerReqNo,
           ContactName = q.ContactName + ISNULL(N' (' + NULLIF(q.ContactTel, N'') + N')', N''),
           q.CustomerName, q.CustAddress, q.CustTel, q.CustEmail,
           SalesContact = q.ControlBy, sp.MobileNo, q.FeeType, q.NoteInItem, q.RemarkReport,
           q.PriceValidity, q.DeliveryTime, q.DeliverTo, q.TermOfPayment, q.CurrencyCode,
           ItemCount = (SELECT COUNT(*) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo AND LineStatus <> 'CANCEL'),
           SubTotal = ISNULL(@sub, 0), q.SpecialDiscount,
           VatAmount  = ROUND((ISNULL(@sub, 0) - q.SpecialDiscount) * @vat / 100, 2),
           GrandTotal = (ISNULL(@sub, 0) - q.SpecialDiscount) + ROUND((ISNULL(@sub, 0) - q.SpecialDiscount) * @vat / 100, 2)
           -- ตัวอักษรบาท (สองหมื่นหนึ่งพัน...สตางค์) ให้รายงานแปลงจาก GrandTotal
    FROM dbo.Qt_Quotation q
    LEFT JOIN dbo.Qt_SaleProfile sp ON sp.SaleName = q.ControlBy
    WHERE q.QNNo = @QNNo;

    SELECT ItemNo = ROW_NUMBER() OVER (ORDER BY i.LineNum),
           Cert17025 = CAST(CASE WHEN i.ANAB = 'ANAB' THEN 1 ELSE 0 END AS BIT),
           CertSub   = CAST(CASE WHEN i.ItemType = N'SUB' THEN 1 ELSE 0 END AS BIT),
           DescriptionText = i.Description + ISNULL(N' ( ' + NULLIF(i.CalID, N'') + N' )', N'')
                           + N' ,SN #' + ISNULL(NULLIF(i.SerialNo, N''), N'-') + N' / ' + ISNULL(NULLIF(i.Manufacturer, N''), N'-') + N' / ' + ISNULL(NULLIF(i.Model, N''), N'-'),
           i.Qty, i.UnitPrice, i.DiscountPct, Amount = i.LineTotal
    FROM dbo.Qt_QuotationItem i
    WHERE i.QNNo = @QNNo AND i.LineStatus <> 'CANCEL';

    SELECT * FROM dbo.Qt_FormSetting WHERE SettingID = 1;
END;
GO

/* ---------------------------------------------------------------------
   10) ประวัติราคาตามรุ่น (แทนหน้า Instrument Detail)
       - ยี่ห้อมาตรฐาน + ชื่อเรียกอื่น (Agilent / HP / Hewlett Packard / Keysight)
       - Model ที่ตัดช่องว่าง/ขีด/จุด เพื่อจับคู่รุ่นเดียวกัน
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_Manufacturer') IS NULL
BEGIN
    CREATE TABLE dbo.Qt_Manufacturer (ManufID INT IDENTITY PRIMARY KEY, ManufName NVARCHAR(100) NOT NULL UNIQUE);
    CREATE TABLE dbo.Qt_ManufacturerAlias (AliasName NVARCHAR(100) NOT NULL PRIMARY KEY, ManufID INT NOT NULL REFERENCES dbo.Qt_Manufacturer(ManufID));
    INSERT dbo.Qt_Manufacturer (ManufName) VALUES (N'Keysight (Agilent / HP)');
    INSERT dbo.Qt_ManufacturerAlias (AliasName, ManufID)
    SELECT v.a, m.ManufID FROM dbo.Qt_Manufacturer m
    CROSS JOIN (VALUES (N'Keysight'),(N'Agilent'),(N'Agilent Technologies'),(N'Hewlett Packard'),(N'HEWLETT-PACKARD'),(N'HP')) v(a)
    WHERE m.ManufName = N'Keysight (Agilent / HP)';
END;
GO

IF COL_LENGTH('dbo.Qt_QuotationItem','ModelKey') IS NULL
    ALTER TABLE dbo.Qt_QuotationItem ADD ModelKey AS CAST(UPPER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(Model, N''), N' ', N''), N'-', N''), N'.', N''), N'/', N''), N'_', N'')) AS NVARCHAR(100)) PERSISTED;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_QtI_ModelKey')
    CREATE INDEX IX_QtI_ModelKey ON dbo.Qt_QuotationItem (ModelKey) INCLUDE (UnitPrice, DiscountPct, Manufacturer, LineStatus);
GO

CREATE OR ALTER VIEW dbo.v_Qt_PriceHistory
AS
SELECT q.QNNo, QuoDate = ISNULL(q.SubmitDate, CAST(q.CreatedAt AS DATE)), q.CustomerID, q.CustomerName, q.ControlBy,
       i.LineNum, i.CalID, i.Description, i.Model, i.ModelKey, i.Manufacturer,
       ManufStd = ISNULL(m.ManufName, i.Manufacturer), i.SerialNo,
       i.UnitPrice, i.DiscountPct, NetPrice = ROUND(i.UnitPrice * (1 - i.DiscountPct / 100), 2), i.TISI, i.ANAB, IsSub = CAST(CASE WHEN i.ItemType = N'SUB' THEN 1 ELSE 0 END AS BIT),
       Result = CASE WHEN i.LineStatus IN ('PO','JOB','INV') THEN 'WON' WHEN i.LineStatus = 'LOST' THEN 'LOST' WHEN i.LineStatus = 'CANCEL' THEN 'CANCEL' ELSE 'WAIT' END
FROM dbo.Qt_QuotationItem i
JOIN dbo.Qt_Quotation q ON q.QNNo = i.QNNo
LEFT JOIN dbo.Qt_ManufacturerAlias a ON a.AliasName = i.Manufacturer
LEFT JOIN dbo.Qt_Manufacturer m ON m.ManufID = a.ManufID
WHERE q.QStatus <> 'DRAFT';
GO

/* ปุ่ม 📈 ในแท็บ Calculation Items : (1) สรุปช่วงราคา 12 เดือน (2) ลูกค้ารายนี้ (3) ลูกค้ารายอื่น */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_PriceHistory @Model NVARCHAR(100), @CustomerID NVARCHAR(20) = NULL, @Months INT = 12
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k NVARCHAR(100) = UPPER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(@Model, N''), N' ', N''), N'-', N''), N'.', N''), N'/', N''), N'_', N''));
    DECLARE @from DATE = DATEADD(MONTH, -@Months, CAST(GETDATE() AS DATE));

    SELECT Cnt = COUNT(*), LastPrice = (SELECT TOP (1) NetPrice FROM dbo.v_Qt_PriceHistory WHERE ModelKey = @k ORDER BY QuoDate DESC),
           MinPrice = MIN(NetPrice), AvgPrice = AVG(NetPrice), MaxPrice = MAX(NetPrice),
           AvgWonPrice = AVG(CASE WHEN Result = 'WON' THEN NetPrice END),
           AvgLostPrice = AVG(CASE WHEN Result = 'LOST' THEN NetPrice END)
    FROM dbo.v_Qt_PriceHistory WHERE ModelKey = @k AND QuoDate >= @from;

    SELECT TOP (50) * FROM dbo.v_Qt_PriceHistory WHERE ModelKey = @k AND CustomerID = @CustomerID ORDER BY QuoDate DESC;
    SELECT TOP (200) * FROM dbo.v_Qt_PriceHistory WHERE ModelKey = @k AND (@CustomerID IS NULL OR CustomerID <> @CustomerID) ORDER BY QuoDate DESC;
END;
GO

/* ปุ่ม "รายการเครื่องตามรุ่น" ในหน้า Quotation List (ค้นแบบกว้างเหมือนหน้าเดิม) */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_InstrumentSearch @Model NVARCHAR(100) = NULL, @Manuf NVARCHAR(100) = NULL, @CustomerID NVARCHAR(20) = NULL, @QNNo NVARCHAR(30) = NULL, @Year INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k NVARCHAR(100) = NULLIF(UPPER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(@Model, N''), N' ', N''), N'-', N''), N'.', N''), N'/', N''), N'_', N'')), N'');
    SELECT TOP (5000) *
    FROM dbo.v_Qt_PriceHistory
    WHERE (@k IS NULL OR ModelKey LIKE @k + N'%')
      AND (@Manuf IS NULL OR Manufacturer LIKE N'%' + @Manuf + N'%' OR ManufStd LIKE N'%' + @Manuf + N'%')
      AND (@CustomerID IS NULL OR CustomerID = @CustomerID)
      AND (@QNNo IS NULL OR QNNo LIKE N'%' + @QNNo + N'%')
      AND (@Year IS NULL OR YEAR(QuoDate) = @Year)
    ORDER BY QuoDate DESC, QNNo, LineNum;
END;
GO

/* ตัวอย่าง
   EXEC dbo.sp_Qt_RecallCandidates @CustomerID = N'CUS00966';
   EXEC dbo.sp_Qt_AddRecallLines @QNNo = N'QN12963/26', @RecallIDs = '101,102,103', @UserName = N'Ms. Nuttiya';
   EXEC dbo.sp_Qt_UpdateLines @QNNo = N'QN12701/26', @LineNums = '1', @LineStatus = 'PO', @PONo = N'PO-2645558';
   EXEC dbo.sp_Qt_UpdateLines @QNNo = N'QN12701/26', @LineNums = '2', @LineStatus = 'LOST', @ReasonCode = 'PRICE';
   EXEC dbo.sp_Qt_NewRevision @QNNo = N'QN12701/26', @UserName = N'Ms. Nattaya';
   EXEC dbo.sp_Qt_CopyQuotation @FromQNNo = N'QN12701/26';
   SELECT * FROM dbo.v_Qt_MarginPct WHERE BelowTarget = 1;
   SELECT ControlBy, ForecastMonth, SUM(ForecastValue) FROM dbo.v_Qt_Forecast GROUP BY ControlBy, ForecastMonth;
   EXEC dbo.sp_Qt_PrintForm @QNNo = N'QN00008/26';
   EXEC dbo.sp_Qt_PriceHistory @Model = N'34401A', @CustomerID = N'CUS01707';
   EXEC dbo.sp_Qt_InstrumentSearch @Model = N'34401A';
*/
