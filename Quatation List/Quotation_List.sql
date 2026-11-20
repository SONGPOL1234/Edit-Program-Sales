/* =====================================================================
   Quotation List (ออกแบบใหม่)  -  SQL Server 2016 SP1 ขึ้นไป
   ใช้คู่กับ Recall_System.sql (ตาราง Rc_*)  ต้องรันสคริปต์ Recall ก่อน
   ---------------------------------------------------------------------
   สิ่งที่เพิ่มจากหน้าจอเดิม
   1) เชื่อมกับ Recall : ใบเสนอราคาเก็บรายการเครื่อง (Qt_QuotationItem)
      อ้างอิง EquipmentID / RecallID / RN เดิม  จึงย้อนดูได้ว่า QN ใบนี้ออกจากงาน Recall ไหน
      และหน้า Recall รู้ว่าเครื่องไหนมี QN รอบใหม่แล้ว
   2) สร้างจาก Recall แล้วเติมให้อัตโนมัติ : ลูกค้า, Customer ID, Control By (Sale ของเครื่อง),
      ราคา (ราคาครั้งก่อนต่อเครื่อง), Subject, Remark อ้าง RN เดิม   -> sp_Qt_CreateFromRecall
   3) ค้นหาด้วย Customer ID, สถานะ (รอ PO / ได้ PO / รับงานแล้ว / ไม่ได้งาน), RN, Cal. ID, PO  -> sp_Qt_Search
   4) สถานะเป็น workflow : DRAFT -> WAIT_PO -> PO_RECEIVED -> JOB_RECEIVED  (หรือ LOST / CANCELLED)
      ทุกการเปลี่ยนสถานะเก็บใน Qt_StatusHist และอัปเดตสถานะงาน Recall ให้ตรงกัน
        WAIT_PO      -> Rc_RecallTask = QUOTED
        PO_RECEIVED  -> Rc_RecallTask = ACCEPTED
        JOB_RECEIVED -> Rc_RecallTask = SCHEDULED (และ RECEIVED เมื่อ sp_Rc_RunDaily พบผลสอบเทียบใหม่)
        LOST / CANCELLED -> Rc_RecallTask กลับเป็น OPEN / OVERDUE

   หมายเหตุ: ชื่อตารางขึ้นต้น Qt_ เพื่อไม่ชนกับตารางใบเสนอราคาเดิม
   ถ้าจะใช้ตารางเดิมต่อ ให้เพิ่มคอลัมน์ CustomerID, QStatus, SourceType ในตารางเดิม
   แล้วใช้ Qt_QuotationItem / Qt_StatusHist เป็นตารางเสริม (QNNo เป็นตัวเชื่อม)
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   1) สถานะ (lookup)
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_Status') IS NULL
BEGIN
    CREATE TABLE dbo.Qt_Status (
        QStatus     VARCHAR(12)  PRIMARY KEY,
        StatusText  NVARCHAR(50) NOT NULL,
        SortOrder   TINYINT      NOT NULL,
        IsOpen      BIT          NOT NULL      -- 1 = ยังต้องติดตาม
    );
    INSERT dbo.Qt_Status VALUES
      ('DRAFT',        N'ร่าง (ยังไม่ส่ง)',     1, 1),
      ('WAIT_PO',      N'รอ PO',               2, 1),
      ('PO_RECEIVED',  N'ได้ PO แล้ว',          3, 1),
      ('JOB_RECEIVED', N'รับงานแล้ว (มี RN)',   4, 0),
      ('LOST',         N'ไม่ได้งาน',            5, 0),
      ('CANCELLED',    N'ยกเลิก',               6, 0);
END;
GO

/* ---------------------------------------------------------------------
   2) หัวใบเสนอราคา : ฟิลด์ตามหน้าจอเดิม + CustomerID / สถานะ / ที่มา
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_Quotation') IS NULL
BEGIN
CREATE TABLE dbo.Qt_Quotation (
    QNNo            NVARCHAR(30)  NOT NULL PRIMARY KEY,         -- QN00123/26
    QNYear          AS TRY_CONVERT(INT, '20' + RIGHT(QNNo, 2)) PERSISTED,
    CustomerID      NVARCHAR(20)  NULL,                          -- รหัสลูกค้า (ค้นหาได้)
    CustomerName    NVARCHAR(255) NOT NULL,
    InquiryDate     DATE          NULL,                          -- Received Inquiry Date
    SubmitDate      DATE          NULL,                          -- Quotation Submit Date (NULL = ยังไม่ส่ง)
    DueDate         DATE          NULL,                          -- ยืนราคาถึง
    QuotationType   NVARCHAR(30)  NOT NULL DEFAULT N'Calibration',
    Subject         NVARCHAR(255) NULL DEFAULT N'Calibration Fee',
    QuoPrice        DECIMAL(18,2) NOT NULL DEFAULT 0,
    CurrencyCode    CHAR(3)       NOT NULL DEFAULT 'THB',
    ControlBy       NVARCHAR(100) NULL,                          -- Sale ผู้ดูแล
    PONo            NVARCHAR(50)  NULL,
    PODate          DATE          NULL,
    OrderReceived   DECIMAL(18,2) NULL,                          -- บาท
    OrderNo         NVARCHAR(50)  NULL,
    ContactName     NVARCHAR(150) NULL,                          -- ผู้ติดต่อฝั่งลูกค้า (จากหน้า Sale Tracking เดิม)
    ContactTel      NVARCHAR(50)  NULL,
    InvoiceNo       NVARCHAR(30)  NULL,
    InvoiceDate     DATE          NULL,                          -- ใช้กรองเดือน Invoice
    QStatus         VARCHAR(12)   NOT NULL DEFAULT 'DRAFT' REFERENCES dbo.Qt_Status(QStatus),
    SourceType      CHAR(1)       NOT NULL DEFAULT 'M' CHECK (SourceType IN ('M','R')),  -- M=สร้างเอง R=จาก Recall
    SplitMode       VARCHAR(4)    NULL,                          -- ALL / QN / RN / ITEM (เมื่อสร้างจาก Recall)
    LostReasonCode  VARCHAR(20)   NULL,                          -- ชุดเดียวกับ Recall (dbo.Rc_CancelReason)
    LostReason      NVARCHAR(255) NULL,                          -- รายละเอียดเพิ่มเติม
    Remarks         NVARCHAR(1000) NULL,                         -- Remarks (Internal)
    CreatedBy       NVARCHAR(100) NULL,
    CreatedAt       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    UpdatedBy       NVARCHAR(100) NULL,
    UpdatedAt       DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX IX_Qt_Quotation_Cust   ON dbo.Qt_Quotation(CustomerID, QNYear) INCLUDE (QStatus, QuoPrice);
CREATE INDEX IX_Qt_Quotation_Status ON dbo.Qt_Quotation(QStatus, SubmitDate) INCLUDE (CustomerID, ControlBy);
CREATE INDEX IX_Qt_Quotation_PO     ON dbo.Qt_Quotation(PONo) WHERE PONo IS NOT NULL;
END;
GO

/* ฟิลด์ที่ย้ายมาจากหน้า Sale Tracking เดิม (สำหรับฐานข้อมูลที่สร้างตารางไปแล้ว) */
IF COL_LENGTH('dbo.Qt_Quotation','ContactName') IS NULL ALTER TABLE dbo.Qt_Quotation ADD ContactName NVARCHAR(150) NULL, ContactTel NVARCHAR(50) NULL;
IF COL_LENGTH('dbo.Qt_Quotation','InvoiceNo')   IS NULL ALTER TABLE dbo.Qt_Quotation ADD InvoiceNo NVARCHAR(30) NULL, InvoiceDate DATE NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Qt_Quotation_Invoice')
    CREATE INDEX IX_Qt_Quotation_Invoice ON dbo.Qt_Quotation(InvoiceDate) WHERE InvoiceDate IS NOT NULL;
GO

/* เหตุผลไม่ได้งาน : ใช้ตารางเดียวกับ Recall + เพิ่ม BUDGET */
IF COL_LENGTH('dbo.Qt_Quotation','LostReasonCode') IS NULL
    ALTER TABLE dbo.Qt_Quotation ADD LostReasonCode VARCHAR(20) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Rc_CancelReason WHERE ReasonCode = 'BUDGET')
    INSERT dbo.Rc_CancelReason (ReasonCode, ReasonText, StopRecall) VALUES ('BUDGET', N'ยกเลิก / ตัดงบประมาณ', 0);
GO
IF OBJECT_ID('dbo.FK_Qt_LostReason') IS NULL
    ALTER TABLE dbo.Qt_Quotation ADD CONSTRAINT FK_Qt_LostReason FOREIGN KEY (LostReasonCode) REFERENCES dbo.Rc_CancelReason(ReasonCode);
GO

/* ---------------------------------------------------------------------
   3) เลข RN ที่เกิดจากใบเสนอราคา (Request No.)  1 QN มีได้หลาย RN
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_QuotationRN') IS NULL
CREATE TABLE dbo.Qt_QuotationRN (
    QNNo       NVARCHAR(30) NOT NULL REFERENCES dbo.Qt_Quotation(QNNo),
    ReceiveNo  NVARCHAR(30) NOT NULL,
    RecDate    DATE NULL,
    CONSTRAINT PK_Qt_QuotationRN PRIMARY KEY (QNNo, ReceiveNo)
);
GO

/* ---------------------------------------------------------------------
   4) รายการเครื่องในใบเสนอราคา : ตัวเชื่อมกับ Recall
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_QuotationItem') IS NULL
BEGIN
CREATE TABLE dbo.Qt_QuotationItem (
    QNNo          NVARCHAR(30)  NOT NULL REFERENCES dbo.Qt_Quotation(QNNo),
    LineNum        INT           NOT NULL,
    EquipmentID   INT           NULL REFERENCES dbo.Rc_Equipment(EquipmentID),
    RecallID      INT           NULL REFERENCES dbo.Rc_RecallTask(RecallID),   -- งาน recall ที่ทำให้ออก QN นี้
    CalID         NVARCHAR(50)  NULL,
    Description   NVARCHAR(255) NULL,
    SerialNo      NVARCHAR(100) NULL,
    OldReceiveNo  NVARCHAR(30)  NULL,          -- RN ครั้งก่อน (อ้างอิง)
    OldQNNo       NVARCHAR(30)  NULL,          -- QN ครั้งก่อน
    DueDate       DATE          NULL,
    UnitPrice     DECIMAL(18,2) NOT NULL DEFAULT 0,
    NewReceiveNo  NVARCHAR(30)  NULL,          -- RN รอบใหม่ (เติมเมื่อรับเครื่อง)
    CONSTRAINT PK_Qt_QuotationItem PRIMARY KEY (QNNo, LineNum)
);
CREATE INDEX IX_Qt_Item_Recall ON dbo.Qt_QuotationItem(RecallID) WHERE RecallID IS NOT NULL;
CREATE INDEX IX_Qt_Item_CalID  ON dbo.Qt_QuotationItem(CalID) INCLUDE (QNNo);
END;
GO

/* ---------------------------------------------------------------------
   5) ประวัติสถานะ
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_StatusHist') IS NULL
CREATE TABLE dbo.Qt_StatusHist (
    HistID     INT IDENTITY(1,1) PRIMARY KEY,
    QNNo       NVARCHAR(30) NOT NULL REFERENCES dbo.Qt_Quotation(QNNo),
    FromStatus VARCHAR(12)  NULL,
    ToStatus   VARCHAR(12)  NOT NULL,
    Note       NVARCHAR(500) NULL,
    ChangedBy  NVARCHAR(100) NULL,
    ChangedAt  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO

/* =====================================================================
   VIEW : รายการสำหรับ grid
   ===================================================================== */
CREATE OR ALTER VIEW dbo.v_Qt_QuotationList
AS
SELECT
    q.QNNo, q.QNYear, q.SourceType,
    SourceText   = CASE q.SourceType WHEN 'R' THEN N'จาก Recall' ELSE N'สร้างเอง' END,
    q.QStatus, s.StatusText, s.SortOrder, s.IsOpen,
    q.CustomerID, q.CustomerName, q.InquiryDate, q.SubmitDate, q.DueDate,
    q.QuotationType, q.Subject, q.QuoPrice, q.CurrencyCode, q.ControlBy,
    q.ContactName, q.ContactTel, q.InvoiceNo, q.InvoiceDate,
    q.PONo, q.PODate, q.OrderReceived, q.OrderNo, q.LostReasonCode, LostReasonText = cr.ReasonText, q.LostReason, q.Remarks,
    DaysToPO     = CASE WHEN q.PODate IS NOT NULL AND q.SubmitDate IS NOT NULL THEN DATEDIFF(DAY, q.SubmitDate, q.PODate) END,
    RequestNo    = STUFF((SELECT N', ' + r.ReceiveNo FROM dbo.Qt_QuotationRN r WHERE r.QNNo = q.QNNo ORDER BY r.ReceiveNo FOR XML PATH('')), 1, 2, ''),
    OldRNList    = STUFF((SELECT DISTINCT N', ' + i.OldReceiveNo FROM dbo.Qt_QuotationItem i WHERE i.QNNo = q.QNNo AND i.OldReceiveNo IS NOT NULL FOR XML PATH('')), 1, 2, ''),
    ItemCount    = (SELECT COUNT(*) FROM dbo.Qt_QuotationItem i WHERE i.QNNo = q.QNNo),
    ReturnedCount= (SELECT COUNT(*) FROM dbo.Qt_QuotationItem i WHERE i.QNNo = q.QNNo AND i.NewReceiveNo IS NOT NULL),
    WaitPODays   = CASE WHEN q.QStatus = 'WAIT_PO' AND q.SubmitDate IS NOT NULL
                        THEN DATEDIFF(DAY, q.SubmitDate, CAST(GETDATE() AS DATE)) END,
    IsExpired    = CASE WHEN q.QStatus IN ('DRAFT','WAIT_PO') AND q.DueDate < CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END
FROM dbo.Qt_Quotation q
JOIN dbo.Qt_Status s ON s.QStatus = q.QStatus
LEFT JOIN dbo.Rc_CancelReason cr ON cr.ReasonCode = q.LostReasonCode;
GO

/* =====================================================================
   SP : ค้นหา (หน้าจอ Quotation List)
   ทุกพารามิเตอร์ NULL = ไม่กรอง
   @CustomerIDs  = 'CUS00966,CUS01707'
   @Statuses     = 'WAIT_PO,PO_RECEIVED'
   @Text         = ค้น RN / Cal. ID / Serial ในรายการเครื่องด้วย
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_Search
    @CustomerIDs  NVARCHAR(MAX) = NULL,
    @CustomerName NVARCHAR(255) = NULL,
    @Year         INT           = NULL,
    @QNNo         NVARCHAR(30)  = NULL,
    @PONo         NVARCHAR(50)  = NULL,
    @Text         NVARCHAR(100) = NULL,
    @ControlBy    NVARCHAR(100) = NULL,
    @SourceType   CHAR(1)       = NULL,
    @Statuses     NVARCHAR(200) = NULL,
    @SubmitFrom   DATE          = NULL,
    @SubmitTo     DATE          = NULL,
    @WaitPOOver   INT           = NULL,       -- เช่น 14 = รอ PO เกิน 14 วัน
    @QuotationType NVARCHAR(30) = NULL,       -- Calibration / Repair / Sale ...
    @InvoiceMonth CHAR(7)       = NULL,       -- 'yyyy-MM' (ช่อง Month (Inv.) ของหน้า Sale Tracking เดิม)
    @Login        NVARCHAR(128) = NULL        -- ผู้ใช้ที่ login: role SALE เห็นเฉพาะ QN ของตัวเอง
AS
BEGIN
    SET NOCOUNT ON;
    /* สิทธิ์: Sales Manager / GM / MD / ADMIN เห็นทั้งหมด ส่วน SALE ถูกบังคับ @ControlBy เป็นชื่อตัวเอง (ตาราง Sys_UserRole อยู่ส่วน 2.4) */
    SET @Login = ISNULL(@Login, SUSER_SNAME());
    IF NOT EXISTS (SELECT 1 FROM dbo.Sys_UserRole WHERE LoginName = @Login AND IsActive = 1 AND RoleCode IN ('SALES_MGR','GM','MD','ADMIN'))
    BEGIN
        DECLARE @own NVARCHAR(100) = (SELECT TOP 1 SaleName FROM dbo.Sys_UserRole WHERE LoginName = @Login AND IsActive = 1 AND RoleCode = 'SALE');
        IF @own IS NULL THROW 50101, N'ไม่มีสิทธิ์ดูรายการใบเสนอราคา', 1;
        SET @ControlBy = @own;
    END;
    SELECT l.*
    FROM dbo.v_Qt_QuotationList l
    WHERE (@CustomerIDs  IS NULL OR l.CustomerID IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@CustomerIDs, ',')))
      AND (@CustomerName IS NULL OR l.CustomerName LIKE N'%' + @CustomerName + N'%')
      AND (@Year         IS NULL OR l.QNYear = @Year)
      AND (@QNNo         IS NULL OR l.QNNo LIKE N'%' + @QNNo + N'%')
      AND (@PONo         IS NULL OR l.PONo LIKE N'%' + @PONo + N'%')
      AND (@ControlBy    IS NULL OR l.ControlBy = @ControlBy)
      AND (@SourceType   IS NULL OR l.SourceType = @SourceType)
      AND (@Statuses     IS NULL OR l.QStatus IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Statuses, ',')))
      AND (@SubmitFrom   IS NULL OR l.SubmitDate >= @SubmitFrom)
      AND (@SubmitTo     IS NULL OR l.SubmitDate <= @SubmitTo)
      AND (@WaitPOOver   IS NULL OR l.WaitPODays > @WaitPOOver)
      AND (@QuotationType IS NULL OR l.QuotationType = @QuotationType)
      AND (@InvoiceMonth IS NULL OR (l.InvoiceDate >= CONVERT(DATE, @InvoiceMonth + '-01')
                                     AND l.InvoiceDate < DATEADD(MONTH, 1, CONVERT(DATE, @InvoiceMonth + '-01'))))
      AND (@Text IS NULL
           OR EXISTS (SELECT 1 FROM dbo.Qt_QuotationRN r WHERE r.QNNo = l.QNNo AND r.ReceiveNo LIKE N'%' + @Text + N'%')
           OR EXISTS (SELECT 1 FROM dbo.Qt_QuotationItem i WHERE i.QNNo = l.QNNo
                      AND (i.CalID LIKE N'%' + @Text + N'%' OR i.SerialNo LIKE N'%' + @Text + N'%'
                           OR i.OldReceiveNo LIKE N'%' + @Text + N'%' OR i.NewReceiveNo LIKE N'%' + @Text + N'%')))
    ORDER BY l.QNYear DESC, l.QNNo DESC
    OPTION (RECOMPILE);
END;
GO

/* KPI หัวจอ (ใช้เงื่อนไขเดียวกับการค้นหา ยกเว้นสถานะ) */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_Summary
    @CustomerIDs NVARCHAR(MAX) = NULL, @Year INT = NULL, @ControlBy NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.QStatus, l.StatusText,
           QNCount   = COUNT(*),
           QuoAmount = SUM(l.QuoPrice),
           OrderAmt  = SUM(ISNULL(l.OrderReceived, 0)),
           WaitOver14= SUM(CASE WHEN l.WaitPODays > 14 THEN 1 ELSE 0 END),
           FromRecall= SUM(CASE WHEN l.SourceType = 'R' THEN 1 ELSE 0 END)
    FROM dbo.v_Qt_QuotationList l
    WHERE (@CustomerIDs IS NULL OR l.CustomerID IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@CustomerIDs, ',')))
      AND (@Year IS NULL OR l.QNYear = @Year)
      AND (@ControlBy IS NULL OR l.ControlBy = @ControlBy)
    GROUP BY l.QStatus, l.StatusText, l.SortOrder
    ORDER BY l.SortOrder;
END;
GO

/* =====================================================================
   SP : เลข QN ถัดไป  QNnnnnn/yy
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_NextNo @QNNo NVARCHAR(30) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @yy CHAR(2) = RIGHT(CONVERT(CHAR(4), YEAR(GETDATE())), 2);
    DECLARE @n INT = ISNULL((SELECT MAX(TRY_CONVERT(INT, SUBSTRING(QNNo, 3, CHARINDEX('/', QNNo) - 3)))
                             FROM dbo.Qt_Quotation WITH (UPDLOCK, HOLDLOCK)
                             WHERE QNNo LIKE N'QN%/' + @yy), 0) + 1;
    SET @QNNo = N'QN' + RIGHT('00000' + CONVERT(VARCHAR(10), @n), 5) + N'/' + @yy;
END;
GO

/* =====================================================================
   SP : สร้างใบเสนอราคาจากงาน Recall + เติมข้อมูลอัตโนมัติ
   @SplitMode  ALL = รวมเป็น 1 ใบ / QN = 1 ใบต่อ QN เดิม / RN = 1 ใบต่อ RN เดิม / ITEM = ใบละเครื่อง
   เติมให้: CustomerID, CustomerName, ControlBy (Sale ที่ดูแลเครื่องมากที่สุด),
            QuoPrice (ผลรวมราคาครั้งก่อน), Subject (เดือนที่ครบกำหนด), Remarks (RN เดิม)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_CreateFromRecall
    @RecallIDs  NVARCHAR(MAX),
    @SplitMode  VARCHAR(4) = 'QN',
    @CreatedBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @SplitMode NOT IN ('ALL','QN','RN','ITEM') THROW 50001, N'SplitMode ต้องเป็น ALL / QN / RN / ITEM', 1;

    /* เครื่องที่ออกได้: ยังไม่กลับมา/ไม่ยกเลิก และยังไม่อยู่ใน QN ที่ยังใช้งานอยู่ */
    SELECT l.RecallID, l.EquipmentID, l.CalID, l.Description, l.SerialNo, l.DueDate,
           l.CustomerID, l.EndUserName, l.SaleName, l.LastQNNo, l.LastReceiveNo, l.ItemPrice,
           GroupKey = l.EndUserName + N'|' + CASE @SplitMode WHEN 'ALL' THEN N'*'
                                                              WHEN 'QN'  THEN ISNULL(l.LastQNNo, N'-')
                                                              WHEN 'RN'  THEN l.LastReceiveNo
                                                              ELSE CONVERT(NVARCHAR(20), l.RecallID) END
    INTO #it
    FROM dbo.v_Rc_RecallList l
    JOIN STRING_SPLIT(@RecallIDs, ',') s ON TRY_CONVERT(INT, s.value) = l.RecallID
    WHERE l.RecallStatus NOT IN ('RECEIVED','CANCELLED')
      AND NOT EXISTS (SELECT 1 FROM dbo.Qt_QuotationItem qi
                      JOIN dbo.Qt_Quotation q ON q.QNNo = qi.QNNo AND q.QStatus NOT IN ('LOST','CANCELLED')
                      WHERE qi.RecallID = l.RecallID);

    IF NOT EXISTS (SELECT 1 FROM #it) THROW 50002, N'ไม่มีเครื่องที่ออกใบเสนอราคาได้ (อาจมี QN อยู่แล้ว)', 1;

    CREATE TABLE #q (GroupKey NVARCHAR(400) PRIMARY KEY, QNNo NVARCHAR(30) NULL);
    INSERT #q (GroupKey) SELECT DISTINCT GroupKey FROM #it;

    BEGIN TRAN;
    DECLARE @k NVARCHAR(400), @no NVARCHAR(30);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT GroupKey FROM #q ORDER BY GroupKey;
    OPEN c; FETCH NEXT FROM c INTO @k;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.sp_Qt_NextNo @QNNo = @no OUTPUT;

        INSERT dbo.Qt_Quotation (QNNo, CustomerID, CustomerName, InquiryDate, DueDate, QuotationType, Subject,
                                 QuoPrice, ControlBy, QStatus, SourceType, SplitMode, Remarks, CreatedBy, UpdatedBy)
        SELECT @no, MAX(i.CustomerID), MAX(i.EndUserName), CAST(GETDATE() AS DATE), DATEADD(DAY, 30, CAST(GETDATE() AS DATE)),
               N'Calibration',
               N'Calibration Fee - Recall ' + FORMAT(MIN(i.DueDate), 'MMM yy') +
                   CASE WHEN FORMAT(MIN(i.DueDate),'yyyyMM') <> FORMAT(MAX(i.DueDate),'yyyyMM') THEN N' - ' + FORMAT(MAX(i.DueDate), 'MMM yy') ELSE N'' END +
                   N' (' + CONVERT(NVARCHAR(10), COUNT(*)) + N' เครื่อง)',
               SUM(i.ItemPrice),
               (SELECT TOP 1 i2.SaleName FROM #it i2 WHERE i2.GroupKey = @k AND i2.SaleName IS NOT NULL
                GROUP BY i2.SaleName ORDER BY COUNT(*) DESC),
               'DRAFT', 'R', @SplitMode,
               N'ออกจาก Recall: RN เดิม ' + STUFF((SELECT DISTINCT N', ' + i3.LastReceiveNo FROM #it i3 WHERE i3.GroupKey = @k FOR XML PATH('')), 1, 2, ''),
               @CreatedBy, @CreatedBy
        FROM #it i WHERE i.GroupKey = @k;

        INSERT dbo.Qt_QuotationItem (QNNo, LineNum, EquipmentID, RecallID, CalID, Description, SerialNo, OldReceiveNo, OldQNNo, DueDate, UnitPrice)
        SELECT @no, ROW_NUMBER() OVER (ORDER BY i.DueDate, i.CalID), i.EquipmentID, i.RecallID, i.CalID, i.Description, i.SerialNo,
               i.LastReceiveNo, i.LastQNNo, i.DueDate, i.ItemPrice
        FROM #it i WHERE i.GroupKey = @k;

        INSERT dbo.Qt_StatusHist (QNNo, FromStatus, ToStatus, Note, ChangedBy)
        VALUES (@no, NULL, 'DRAFT', N'สร้างจาก Recall', @CreatedBy);

        UPDATE #q SET QNNo = @no WHERE GroupKey = @k;
        FETCH NEXT FROM c INTO @k;
    END;
    CLOSE c; DEALLOCATE c;

    /* ให้หน้า Recall เห็นเลข QN ใหม่ */
    UPDATE t SET NewQNNo = q.QNNo, UpdatedAt = SYSDATETIME()
    FROM dbo.Rc_RecallTask t JOIN #it i ON i.RecallID = t.RecallID JOIN #q q ON q.GroupKey = i.GroupKey;
    COMMIT;

    SELECT l.* FROM dbo.v_Qt_QuotationList l JOIN #q q ON q.QNNo = l.QNNo ORDER BY l.QNNo;
END;
GO

/* =====================================================================
   SP : บันทึก (Add / Edit) จากฟอร์ม
   ถ้า @QNNo NULL = เพิ่มใหม่  ถ้าใส่ @CustomerID แต่ไม่ใส่ชื่อ/ControlBy ระบบเติมจากประวัติล่าสุดของลูกค้า
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_Save
    @QNNo          NVARCHAR(30) = NULL OUTPUT,
    @CustomerID    NVARCHAR(20) = NULL,
    @CustomerName  NVARCHAR(255) = NULL,
    @InquiryDate   DATE = NULL, @SubmitDate DATE = NULL, @DueDate DATE = NULL,
    @QuotationType NVARCHAR(30) = N'Calibration', @Subject NVARCHAR(255) = N'Calibration Fee',
    @QuoPrice      DECIMAL(18,2) = 0, @CurrencyCode CHAR(3) = 'THB',
    @ControlBy     NVARCHAR(100) = NULL,
    @PONo NVARCHAR(50) = NULL, @PODate DATE = NULL, @OrderReceived DECIMAL(18,2) = NULL, @OrderNo NVARCHAR(50) = NULL,
    @Remarks       NVARCHAR(1000) = NULL,
    @ContactName   NVARCHAR(150) = NULL, @ContactTel NVARCHAR(50) = NULL,
    @InvoiceNo     NVARCHAR(30) = NULL, @InvoiceDate DATE = NULL,
    @UserName      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @CustomerID IS NOT NULL AND (@CustomerName IS NULL OR @ControlBy IS NULL)
        SELECT TOP 1 @CustomerName = ISNULL(@CustomerName, CustomerName), @ControlBy = ISNULL(@ControlBy, ControlBy)
        FROM dbo.Qt_Quotation WHERE CustomerID = @CustomerID ORDER BY CreatedAt DESC;
    IF @CustomerID IS NOT NULL AND @CustomerName IS NULL
        SELECT TOP 1 @CustomerName = EndUserName, @ControlBy = ISNULL(@ControlBy, SaleName)
        FROM dbo.Rc_Equipment WHERE CustomerID = @CustomerID;
    IF @CustomerName IS NULL THROW 50010, N'กรุณาระบุลูกค้า', 1;
    IF @CustomerID IS NOT NULL AND @ContactName IS NULL      -- เติมผู้ติดต่อจากใบล่าสุดของลูกค้า
        SELECT TOP 1 @ContactName = ContactName, @ContactTel = ISNULL(@ContactTel, ContactTel)
        FROM dbo.Qt_Quotation WHERE CustomerID = @CustomerID AND ContactName IS NOT NULL ORDER BY CreatedAt DESC;

    BEGIN TRAN;
    IF @QNNo IS NULL
    BEGIN
        EXEC dbo.sp_Qt_NextNo @QNNo = @QNNo OUTPUT;
        INSERT dbo.Qt_Quotation (QNNo, CustomerID, CustomerName, InquiryDate, SubmitDate, DueDate, QuotationType, Subject,
                                 QuoPrice, CurrencyCode, ControlBy, PONo, PODate, OrderReceived, OrderNo, Remarks,
                                 ContactName, ContactTel, InvoiceNo, InvoiceDate, CreatedBy, UpdatedBy)
        VALUES (@QNNo, @CustomerID, @CustomerName, ISNULL(@InquiryDate, CAST(GETDATE() AS DATE)), @SubmitDate,
                ISNULL(@DueDate, DATEADD(DAY, 30, ISNULL(@SubmitDate, CAST(GETDATE() AS DATE)))), @QuotationType, @Subject,
                @QuoPrice, @CurrencyCode, @ControlBy, @PONo, @PODate, @OrderReceived, @OrderNo, @Remarks,
                @ContactName, @ContactTel, @InvoiceNo, @InvoiceDate, @UserName, @UserName);
        INSERT dbo.Qt_StatusHist (QNNo, ToStatus, Note, ChangedBy) VALUES (@QNNo, 'DRAFT', N'สร้างใบเสนอราคา', @UserName);
    END
    ELSE
        UPDATE dbo.Qt_Quotation SET
            CustomerID = @CustomerID, CustomerName = @CustomerName, InquiryDate = @InquiryDate, SubmitDate = @SubmitDate,
            DueDate = @DueDate, QuotationType = @QuotationType, Subject = @Subject, QuoPrice = @QuoPrice,
            CurrencyCode = @CurrencyCode, ControlBy = @ControlBy, PONo = @PONo, PODate = @PODate,
            OrderReceived = @OrderReceived, OrderNo = @OrderNo, Remarks = @Remarks,
            ContactName = @ContactName, ContactTel = @ContactTel, InvoiceNo = @InvoiceNo, InvoiceDate = @InvoiceDate,
            UpdatedBy = @UserName, UpdatedAt = SYSDATETIME()
        WHERE QNNo = @QNNo;
    COMMIT;
END;
GO

/* =====================================================================
   SP : เปลี่ยนสถานะ (ปุ่ม ส่งลูกค้า / ได้รับ PO / รับเครื่อง / ไม่ได้งาน / ยกเลิก)
   และอัปเดตงาน Recall ที่ผูกอยู่ให้ตรงกัน
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_SetStatus
    @QNNo          NVARCHAR(30),
    @NewStatus     VARCHAR(12),
    @PONo          NVARCHAR(50)  = NULL,
    @PODate        DATE          = NULL,
    @OrderReceived DECIMAL(18,2) = NULL,
    @ReceiveNo     NVARCHAR(30)  = NULL,        -- RN เมื่อรับเครื่อง (JOB_RECEIVED)
    @ReasonCode    VARCHAR(20)   = NULL,        -- LOST: PRICE / COMPETITOR / BUDGET / ... (dbo.Rc_CancelReason)
    @Note          NVARCHAR(500) = NULL,        -- รายละเอียดเพิ่มเติม
    @UserName      NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @old VARCHAR(12) = (SELECT QStatus FROM dbo.Qt_Quotation WHERE QNNo = @QNNo);
    IF @old IS NULL THROW 50020, N'ไม่พบใบเสนอราคา', 1;
    IF @NewStatus = 'PO_RECEIVED'  AND @PONo IS NULL      THROW 50021, N'กรุณาใส่ PO No.', 1;
    IF @NewStatus = 'JOB_RECEIVED' AND @ReceiveNo IS NULL THROW 50022, N'กรุณาใส่ RN', 1;
    IF @NewStatus = 'LOST' AND NOT EXISTS (SELECT 1 FROM dbo.Rc_CancelReason WHERE ReasonCode = @ReasonCode)
        THROW 50023, N'กรุณาเลือกเหตุผลที่ไม่ได้งาน', 1;
    DECLARE @stop BIT = ISNULL((SELECT StopRecall FROM dbo.Rc_CancelReason WHERE ReasonCode = @ReasonCode), 0);

    BEGIN TRAN;
    UPDATE dbo.Qt_Quotation SET
        QStatus       = @NewStatus,
        SubmitDate    = CASE WHEN @NewStatus = 'WAIT_PO' THEN ISNULL(SubmitDate, CAST(GETDATE() AS DATE)) ELSE SubmitDate END,
        PONo          = ISNULL(@PONo, PONo),
        PODate        = CASE WHEN @PONo IS NOT NULL THEN ISNULL(@PODate, CAST(GETDATE() AS DATE)) ELSE PODate END,
        OrderReceived = CASE WHEN @NewStatus = 'PO_RECEIVED' THEN ISNULL(@OrderReceived, QuoPrice) ELSE OrderReceived END,
        LostReasonCode= CASE WHEN @NewStatus = 'LOST' THEN @ReasonCode ELSE LostReasonCode END,
        LostReason    = CASE WHEN @NewStatus IN ('LOST','CANCELLED') THEN @Note ELSE LostReason END,
        UpdatedBy = @UserName, UpdatedAt = SYSDATETIME()
    WHERE QNNo = @QNNo;

    IF @ReceiveNo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Qt_QuotationRN WHERE QNNo = @QNNo AND ReceiveNo = @ReceiveNo)
        INSERT dbo.Qt_QuotationRN (QNNo, ReceiveNo, RecDate) VALUES (@QNNo, @ReceiveNo, CAST(GETDATE() AS DATE));

    INSERT dbo.Qt_StatusHist (QNNo, FromStatus, ToStatus, Note, ChangedBy)
    VALUES (@QNNo, @old, @NewStatus,
            COALESCE((SELECT ReasonText FROM dbo.Rc_CancelReason WHERE ReasonCode = @ReasonCode) + ISNULL(N' - ' + @Note, N''), @Note, N'PO ' + @PONo, N'RN ' + @ReceiveNo),
            @UserName);

    /* sync งาน Recall */
    UPDATE t SET
        RecallStatus = CASE @NewStatus
                         WHEN 'WAIT_PO'      THEN 'QUOTED'
                         WHEN 'PO_RECEIVED'  THEN 'ACCEPTED'
                         WHEN 'JOB_RECEIVED' THEN 'SCHEDULED'
                         ELSE CASE WHEN @NewStatus = 'LOST' AND @stop = 1 THEN 'CANCELLED'      -- เลิกใช้/ขายเครื่อง: หยุด recall
                                   WHEN t.DueDate < CAST(GETDATE() AS DATE) THEN 'OVERDUE' ELSE 'OPEN' END END,
        NewQNNo      = CASE WHEN @NewStatus IN ('LOST','CANCELLED') THEN NULL ELSE @QNNo END,
        UpdatedAt    = SYSDATETIME()
    FROM dbo.Rc_RecallTask t
    JOIN dbo.Qt_QuotationItem i ON i.RecallID = t.RecallID AND i.QNNo = @QNNo
    WHERE t.RecallStatus NOT IN ('RECEIVED','CANCELLED')
      AND @NewStatus IN ('WAIT_PO','PO_RECEIVED','JOB_RECEIVED','LOST','CANCELLED');
    COMMIT;
END;
GO

/* =====================================================================
   SP : เชื่อม RN รอบใหม่กลับมาที่ใบเสนอราคา (เรียกต่อจาก sp_Rc_RunDaily)
   เมื่อ Rc_CalEvent มีผลสอบเทียบใหม่ที่อ้าง QN นี้ -> เติม NewReceiveNo และปิดเป็น JOB_RECEIVED
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_SyncFromCalEvent
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    UPDATE i SET NewReceiveNo = c.ReceiveNo
    FROM dbo.Qt_QuotationItem i
    JOIN dbo.Rc_CalEvent c ON c.EquipmentID = i.EquipmentID AND c.QNNo = i.QNNo
    WHERE i.NewReceiveNo IS NULL;

    INSERT dbo.Qt_QuotationRN (QNNo, ReceiveNo, RecDate)
    SELECT DISTINCT c.QNNo, c.ReceiveNo, c.RecDate
    FROM dbo.Rc_CalEvent c
    JOIN dbo.Qt_Quotation q ON q.QNNo = c.QNNo
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Qt_QuotationRN r WHERE r.QNNo = c.QNNo AND r.ReceiveNo = c.ReceiveNo);

    INSERT dbo.Qt_StatusHist (QNNo, FromStatus, ToStatus, Note, ChangedBy)
    SELECT q.QNNo, q.QStatus, 'JOB_RECEIVED', N'พบ RN ในระบบ (อัตโนมัติ)', N'system'
    FROM dbo.Qt_Quotation q
    WHERE q.QStatus IN ('DRAFT','WAIT_PO','PO_RECEIVED')
      AND EXISTS (SELECT 1 FROM dbo.Qt_QuotationRN r WHERE r.QNNo = q.QNNo);

    UPDATE q SET QStatus = 'JOB_RECEIVED', OrderReceived = ISNULL(OrderReceived, QuoPrice), UpdatedAt = SYSDATETIME()
    FROM dbo.Qt_Quotation q
    WHERE q.QStatus IN ('DRAFT','WAIT_PO','PO_RECEIVED')
      AND EXISTS (SELECT 1 FROM dbo.Qt_QuotationRN r WHERE r.QNNo = q.QNNo);
    COMMIT;
END;
GO

/* =====================================================================
   ย้ายข้อมูลเดิม (ครั้งเดียว) : สร้าง Qt_Quotation จาก QN ที่อยู่ใน Rc_CalEvent / Rc_Quotation
   ถ้ามีตารางใบเสนอราคาเดิม ให้เปลี่ยนมาอ่านจากตารางนั้นแทน (จะได้ PO / วันที่ส่ง ที่ถูกต้อง)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_MigrateFromRecall
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    ;WITH x AS (
        SELECT c.QNNo, e.CustomerID, e.EndUserName, c.SaleName, c.RecDate, c.CalDate,
               rn = ROW_NUMBER() OVER (PARTITION BY c.QNNo ORDER BY c.CalDate)
        FROM dbo.Rc_CalEvent c JOIN dbo.Rc_Equipment e ON e.EquipmentID = c.EquipmentID
        WHERE c.QNNo LIKE N'QN%/__' AND c.QNNo NOT LIKE N'%,%'
    )
    INSERT dbo.Qt_Quotation (QNNo, CustomerID, CustomerName, SubmitDate, QuoPrice, ControlBy, QStatus, SourceType, OrderReceived, CreatedBy)
    SELECT x.QNNo, x.CustomerID, x.EndUserName, NULL, ISNULL(q.QuoCost, 0), x.SaleName, 'JOB_RECEIVED', 'M', q.QuoCost, N'migrate'
    FROM x LEFT JOIN dbo.Rc_Quotation q ON q.QNNo = x.QNNo
    WHERE x.rn = 1 AND NOT EXISTS (SELECT 1 FROM dbo.Qt_Quotation t WHERE t.QNNo = x.QNNo);

    INSERT dbo.Qt_QuotationRN (QNNo, ReceiveNo, RecDate)
    SELECT DISTINCT c.QNNo, c.ReceiveNo, c.RecDate
    FROM dbo.Rc_CalEvent c JOIN dbo.Qt_Quotation q ON q.QNNo = c.QNNo
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Qt_QuotationRN r WHERE r.QNNo = c.QNNo AND r.ReceiveNo = c.ReceiveNo);

    INSERT dbo.Qt_QuotationItem (QNNo, LineNum, EquipmentID, CalID, Description, SerialNo, OldReceiveNo, DueDate, UnitPrice, NewReceiveNo)
    SELECT c.QNNo, ROW_NUMBER() OVER (PARTITION BY c.QNNo ORDER BY c.ReceiveNo, e.CalID),
           e.EquipmentID, e.CalID, e.Description, e.SerialNo, NULL, c.DueDate,
           COALESCE(c.ItemPrice, c.ItemPriceEst, 0), c.ReceiveNo
    FROM dbo.Rc_CalEvent c JOIN dbo.Rc_Equipment e ON e.EquipmentID = c.EquipmentID
    JOIN dbo.Qt_Quotation q ON q.QNNo = c.QNNo
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Qt_QuotationItem i WHERE i.QNNo = c.QNNo);
    COMMIT;
END;
GO

/* ตัวอย่างการใช้งาน
   EXEC dbo.sp_Qt_MigrateFromRecall;                                           -- ครั้งเดียว
   EXEC dbo.sp_Qt_Search @CustomerIDs = 'CUS00966', @Year = 2026;
   EXEC dbo.sp_Qt_Search @Statuses = 'WAIT_PO', @WaitPOOver = 14;              -- รอ PO เกิน 14 วัน
   EXEC dbo.sp_Qt_Search @Text = N'PCAL180426';
   EXEC dbo.sp_Qt_Search @InvoiceMonth = '2026-03', @QuotationType = N'Calibration';   -- แทนหน้า Sale Tracking
   EXEC dbo.sp_Qt_Search @Login = N'DOMAIN\ratthanin';                                -- Sale เห็นเฉพาะของตัวเอง                                 -- หา QN จากเลขเครื่อง
   EXEC dbo.sp_Qt_CreateFromRecall @RecallIDs = '101,102,103', @SplitMode = 'QN', @CreatedBy = N'Ms. Marasri';
   EXEC dbo.sp_Qt_SetStatus @QNNo = N'QN12701/26', @NewStatus = 'WAIT_PO', @UserName = N'Ms. Marasri';
   EXEC dbo.sp_Qt_SetStatus @QNNo = N'QN12701/26', @NewStatus = 'PO_RECEIVED', @PONo = N'PO-2645558', @UserName = N'Ms. Marasri';
   EXEC dbo.sp_Qt_SetStatus @QNNo = N'QN12701/26', @NewStatus = 'LOST', @ReasonCode = 'PRICE', @Note = N'คู่แข่งถูกกว่า 15%';
   -- เพิ่มต่อท้าย sp_Rc_RunDaily :  EXEC dbo.sp_Qt_SyncFromCalEvent;
*/


/* #####################################################################
   ส่วนที่ 2 : ติดตาม QN ที่ยังไม่ได้ PO / แบบฟอร์มพิมพ์ / Sales Dashboard
   ##################################################################### */

/* ---------------------------------------------------------------------
   2.1 บันทึกการติดตาม (โครงสร้างเดียวกับ Rc_ContactLog ของ Recall)
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_FollowUpResult') IS NULL
BEGIN
    CREATE TABLE dbo.Qt_FollowUpResult (
        ResultCode  VARCHAR(20) PRIMARY KEY,
        ResultText  NVARCHAR(100) NOT NULL,
        NextStatus  VARCHAR(12) NULL              -- ถ้ามีค่า = เปลี่ยนสถานะ QN ตามผลนี้
    );
    INSERT dbo.Qt_FollowUpResult VALUES
      ('CONSIDER',    N'ลูกค้ากำลังพิจารณา',      NULL),
      ('BUDGET_WAIT', N'รออนุมัติงบ',             NULL),
      ('PO_SOON',     N'จะออก PO เร็ว ๆ นี้',      NULL),
      ('REVISE',      N'ขอแก้ไข / ต่อราคา',        NULL),
      ('NO_ANSWER',   N'ติดต่อไม่ได้',             NULL),
      ('PO_RECEIVED', N'ได้รับ PO',               'PO_RECEIVED'),
      ('LOST',        N'ไม่ได้งาน',               'LOST');
END;
GO
IF OBJECT_ID('dbo.Qt_FollowUpLog') IS NULL
BEGIN
CREATE TABLE dbo.Qt_FollowUpLog (
    LogID        INT IDENTITY(1,1) PRIMARY KEY,
    QNNo         NVARCHAR(30)  NOT NULL REFERENCES dbo.Qt_Quotation(QNNo),
    ContactDate  DATE          NOT NULL,
    Channel      VARCHAR(10)   NOT NULL CHECK (Channel IN ('PHONE','EMAIL','LINE','VISIT','OTHER')),   -- ชุดเดียวกับ Recall
    ResultCode   VARCHAR(20)   NOT NULL REFERENCES dbo.Qt_FollowUpResult(ResultCode),
    ContactName  NVARCHAR(150) NULL,
    Note         NVARCHAR(500) NULL,
    NextFollowDate DATE        NULL,
    CreatedBy    NVARCHAR(100) NULL,
    CreatedAt    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
CREATE INDEX IX_Qt_FollowUpLog_QN ON dbo.Qt_FollowUpLog(QNNo, ContactDate DESC);
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Qt_AddFollowUp
    @QNNo NVARCHAR(30), @ContactDate DATE, @Channel VARCHAR(10), @ResultCode VARCHAR(20),
    @ContactName NVARCHAR(150) = NULL, @Note NVARCHAR(500) = NULL, @NextFollowDate DATE = NULL,
    @UserName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    INSERT dbo.Qt_FollowUpLog (QNNo, ContactDate, Channel, ResultCode, ContactName, Note, NextFollowDate, CreatedBy)
    VALUES (@QNNo, @ContactDate, @Channel, @ResultCode, @ContactName, @Note,
            CASE WHEN @ResultCode IN ('PO_RECEIVED','LOST') THEN NULL ELSE @NextFollowDate END, @UserName);
    /* ผล PO_RECEIVED / LOST หน้าจอจะเปิดหน้าต่างให้ใส่ PO หรือเหตุผล แล้วเรียก sp_Qt_SetStatus ต่อ */
END;
GO

/* ---------------------------------------------------------------------
   2.2 QN ที่ต้องติดตาม : รอ PO และส่งไปแล้วครบ 7 / 14 / 30 วัน แต่ยังไม่ได้ติดตามหลังครบรอบนั้น
       หรือถึงวันนัดติดตามที่ Sale บันทึกไว้
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.v_Qt_FollowUpDue
AS
WITH b AS (
    SELECT q.QNNo, q.CustomerID, q.CustomerName, q.ControlBy, q.SubmitDate, q.QuoPrice,
           AgeDays = DATEDIFF(DAY, q.SubmitDate, CAST(GETDATE() AS DATE)),
           LastContact = l.ContactDate, LastResult = r.ResultText, NextFollowDate = l.NextFollowDate
    FROM dbo.Qt_Quotation q
    OUTER APPLY (SELECT TOP 1 * FROM dbo.Qt_FollowUpLog x WHERE x.QNNo = q.QNNo ORDER BY x.ContactDate DESC, x.LogID DESC) l
    LEFT JOIN dbo.Qt_FollowUpResult r ON r.ResultCode = l.ResultCode
    WHERE q.QStatus = 'WAIT_PO' AND q.SubmitDate IS NOT NULL
), lv AS (
    SELECT b.*, Level = CASE WHEN AgeDays >= 30 THEN 30 WHEN AgeDays >= 14 THEN 14 WHEN AgeDays >= 7 THEN 7 ELSE 0 END FROM b
)
SELECT lv.*,
       Reason = CASE WHEN Level > 0 AND (LastContact IS NULL OR LastContact < DATEADD(DAY, Level, SubmitDate))
                     THEN N'ครบ ' + CONVERT(NVARCHAR(3), Level) + N' วัน ยังไม่ติดตาม'
                     ELSE N'ถึงวันนัดติดตาม ' + CONVERT(NVARCHAR(10), NextFollowDate, 103) END
FROM lv
WHERE (Level > 0 AND (LastContact IS NULL OR LastContact < DATEADD(DAY, Level, SubmitDate)))
   OR NextFollowDate <= CAST(GETDATE() AS DATE);
GO

/* อีเมลแจ้งเตือนรายวันถึง Sale (cc หัวหน้า)  ใช้ Rc_SaleContact และ Database Mail เหมือนของ Recall
   ตั้ง SQL Agent Job ทุกเช้า: EXEC dbo.sp_Qt_SendFollowUpMail @Profile = N'CalLab Mail'; */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_SendFollowUpMail
    @Profile SYSNAME = N'CalLab Mail', @PreviewOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sale NVARCHAR(100), @to NVARCHAR(200), @cc NVARCHAR(200), @body NVARCHAR(MAX), @subj NVARCHAR(200), @n INT;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT d.ControlBy, sc.Email, sc.ManagerEmail, COUNT(*)
        FROM dbo.v_Qt_FollowUpDue d JOIN dbo.Rc_SaleContact sc ON sc.SaleName = d.ControlBy AND sc.IsActive = 1
        GROUP BY d.ControlBy, sc.Email, sc.ManagerEmail;
    OPEN c; FETCH NEXT FROM c INTO @sale, @to, @cc, @n;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @subj = N'[แจ้งเตือน] ใบเสนอราคารอ PO ที่ต้องติดตามวันนี้ ' + CONVERT(NVARCHAR(10), @n) + N' ใบ';
        SET @body = N'<p>เรียน คุณ' + @sale + N'</p><p>ใบเสนอราคาต่อไปนี้ส่งให้ลูกค้าแล้วแต่ยังไม่ได้รับ PO กรุณาติดตามและบันทึกผลในหน้า Quotation List</p>'
                  + N'<table border="1" cellpadding="4" style="border-collapse:collapse;font-family:Tahoma;font-size:12px">'
                  + N'<tr style="background:#e8eef6"><th>Quo. No.</th><th>ลูกค้า</th><th>ส่งเมื่อ</th><th>รอมา (วัน)</th><th>สาเหตุ</th><th>ติดตามล่าสุด</th><th>มูลค่า</th></tr>'
                  + (SELECT N'<tr><td>' + d.QNNo + N'</td><td>' + d.CustomerName + N'</td><td>' + CONVERT(NVARCHAR(10), d.SubmitDate, 103)
                          + N'</td><td align="right">' + CONVERT(NVARCHAR(10), d.AgeDays) + N'</td><td>' + d.Reason
                          + N'</td><td>' + ISNULL(CONVERT(NVARCHAR(10), d.LastContact, 103) + N' ' + d.LastResult, N'-')
                          + N'</td><td align="right">' + FORMAT(d.QuoPrice, 'N2') + N'</td></tr>'
                     FROM dbo.v_Qt_FollowUpDue d WHERE d.ControlBy = @sale ORDER BY d.AgeDays DESC
                     FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)')
                  + N'</table>';
        IF @PreviewOnly = 1 SELECT Sale = @sale, ToEmail = @to, Cc = @cc, Subject = @subj, Body = @body;
        ELSE EXEC msdb.dbo.sp_send_dbmail @profile_name = @Profile, @recipients = @to, @copy_recipients = @cc,
                                         @subject = @subj, @body = @body, @body_format = 'HTML';
        FETCH NEXT FROM c INTO @sale, @to, @cc, @n;
    END;
    CLOSE c; DEALLOCATE c;
END;
GO

/* ---------------------------------------------------------------------
   2.3 แบบฟอร์มใบเสนอราคา (พิมพ์ / PDF)
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Qt_FormSetting') IS NULL
BEGIN
    CREATE TABLE dbo.Qt_FormSetting (
        SettingID     TINYINT PRIMARY KEY DEFAULT 1 CHECK (SettingID = 1),   -- มีแถวเดียว
        CompanyNameTh NVARCHAR(200) NOT NULL,
        CompanyNameEn NVARCHAR(200) NULL,
        AddressText   NVARCHAR(500) NULL,
        TaxID         VARCHAR(20)   NULL,
        LogoImage     VARBINARY(MAX) NULL,
        VatRate       DECIMAL(5,2)  NOT NULL DEFAULT 7,
        CreditTerm    NVARCHAR(50)  NULL,
        TermsText     NVARCHAR(2000) NULL,
        ApproverTitle NVARCHAR(100) NULL
    );
    INSERT dbo.Qt_FormSetting (CompanyNameTh, VatRate, CreditTerm) VALUES (N'(ชื่อบริษัท)', 7, N'30 วัน');
END;
GO

/* ข้อมูลสำหรับพิมพ์: 3 result sets  (1) หัวกระดาษ+ยอดเงิน (2) รายการ รวมเครื่องรุ่นเดียวกัน (3) ตั้งค่าแบบฟอร์ม */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_PrintData @QNNo NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @vat DECIMAL(5,2) = (SELECT VatRate FROM dbo.Qt_FormSetting);
    SELECT q.QNNo, q.CustomerID, q.CustomerName, q.SubjectText, q.SubmitDate, q.DueDate, q.ControlBy, q.CurrencyCode,
           SubTotal = ISNULL(i.Total, q.QuoPrice), Discount = CASE WHEN i.Total > q.QuoPrice THEN i.Total - q.QuoPrice ELSE 0 END,
           NetAmount = q.QuoPrice, VatAmount = ROUND(q.QuoPrice * @vat / 100, 2), GrandTotal = q.QuoPrice + ROUND(q.QuoPrice * @vat / 100, 2)
           -- ตัวอักษรภาษาไทย (บาทถ้วน) ให้หน้าจอ/รายงานแปลงเอง หรือใช้ฟังก์ชัน dbo.fn_BahtText ถ้ามีในระบบเดิม
    FROM (SELECT QNNo, CustomerID, CustomerName, SubjectText = Subject, SubmitDate, DueDate, ControlBy, CurrencyCode, QuoPrice
          FROM dbo.Qt_Quotation WHERE QNNo = @QNNo) q
    OUTER APPLY (SELECT Total = SUM(UnitPrice) FROM dbo.Qt_QuotationItem WHERE QNNo = @QNNo) i;

    SELECT LineNumber = ROW_NUMBER() OVER (ORDER BY MIN(i.LineNum)),
           i.Description, e.Model, e.Manuf, i.UnitPrice, Qty = COUNT(*), Amount = SUM(i.UnitPrice),
           IDList = STUFF((SELECT N', ' + i2.CalID + ISNULL(N' (S/N ' + NULLIF(i2.SerialNo, N'') + N')', N'')
                           FROM dbo.Qt_QuotationItem i2 LEFT JOIN dbo.Rc_Equipment e2 ON e2.EquipmentID = i2.EquipmentID
                           WHERE i2.QNNo = @QNNo AND ISNULL(i2.Description,N'') = ISNULL(i.Description,N'')
                             AND ISNULL(e2.Model,N'') = ISNULL(e.Model,N'') AND i2.UnitPrice = i.UnitPrice
                           ORDER BY i2.LineNum FOR XML PATH('')), 1, 2, '')
    FROM dbo.Qt_QuotationItem i LEFT JOIN dbo.Rc_Equipment e ON e.EquipmentID = i.EquipmentID
    WHERE i.QNNo = @QNNo
    GROUP BY i.Description, e.Model, e.Manuf, i.UnitPrice;

    SELECT * FROM dbo.Qt_FormSetting;
END;
GO

/* ---------------------------------------------------------------------
   2.4 Sales Dashboard : สิทธิ์เฉพาะ Sales Manager / GM / MD
   ตรวจสิทธิ์ที่ฐานข้อมูล (หน้า HTML ตรวจซ้ำได้แต่ไม่ใช่ตัวกันจริง)
   แนะนำเพิ่ม: ให้ผู้ใช้หน้าจอ Execute ได้เฉพาะ SP นี้ ไม่ให้ SELECT ตาราง Qt_* ตรง
               และเก็บไฟล์ Dashboard ในโฟลเดอร์แชร์ที่ให้สิทธิ์เฉพาะ 3 ตำแหน่งนี้
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Sys_UserRole') IS NULL
CREATE TABLE dbo.Sys_UserRole (
    LoginName  NVARCHAR(128) NOT NULL,               -- ตรงกับ SUSER_SNAME() หรือ user ของโปรแกรม
    RoleCode   VARCHAR(20)   NOT NULL CHECK (RoleCode IN ('SALES_MGR','GM','MD','SALE','STAFF','ADMIN')),
    SaleName   NVARCHAR(100) NULL,                   -- สำหรับ role SALE (ใช้กรองเห็นเฉพาะของตัวเองในหน้า Quotation List)
    IsActive   BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_Sys_UserRole PRIMARY KEY (LoginName, RoleCode)
);
GO
CREATE OR ALTER FUNCTION dbo.fn_CanViewSalesDashboard (@Login NVARCHAR(128))
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM dbo.Sys_UserRole
                             WHERE LoginName = @Login AND IsActive = 1 AND RoleCode IN ('SALES_MGR','GM','MD'))
                THEN 1 ELSE 0 END;
END;
GO

/* @Login: โปรแกรมส่งชื่อผู้ใช้ที่ login มา (ถ้า NULL ใช้ login ของ SQL)  */
CREATE OR ALTER PROCEDURE dbo.sp_Qt_SalesDashboard
    @From DATE, @To DATE, @SourceType CHAR(1) = NULL, @Login NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Login = ISNULL(@Login, SUSER_SNAME());
    IF dbo.fn_CanViewSalesDashboard(@Login) = 0
        THROW 50100, N'ไม่มีสิทธิ์ดู Sales Dashboard (เฉพาะ Sales Manager, GM, MD)', 1;

    /* 1) สรุปแยกตาม Sale */
    SELECT ControlBy = ISNULL(l.ControlBy, N'(ไม่ระบุ)'),
           QNSent        = COUNT(*),
           QuotedValue   = SUM(l.QuoPrice),
           POWon         = SUM(CASE WHEN l.QStatus IN ('PO_RECEIVED','JOB_RECEIVED') THEN 1 ELSE 0 END),
           WonValue      = SUM(CASE WHEN l.QStatus IN ('PO_RECEIVED','JOB_RECEIVED') THEN ISNULL(l.OrderReceived, l.QuoPrice) ELSE 0 END),
           Lost          = SUM(CASE WHEN l.QStatus = 'LOST' THEN 1 ELSE 0 END),
           LostValue     = SUM(CASE WHEN l.QStatus = 'LOST' THEN l.QuoPrice ELSE 0 END),
           WinRatePct    = CAST(100.0 * SUM(CASE WHEN l.QStatus IN ('PO_RECEIVED','JOB_RECEIVED') THEN 1 ELSE 0 END)
                                / NULLIF(SUM(CASE WHEN l.QStatus IN ('PO_RECEIVED','JOB_RECEIVED','LOST') THEN 1 ELSE 0 END), 0) AS DECIMAL(5,1)),
           WaitingPO     = SUM(CASE WHEN l.QStatus = 'WAIT_PO' THEN 1 ELSE 0 END),
           WaitingValue  = SUM(CASE WHEN l.QStatus = 'WAIT_PO' THEN l.QuoPrice ELSE 0 END),
           WaitingOver14 = SUM(CASE WHEN l.WaitPODays > 14 THEN 1 ELSE 0 END),
           AvgDaysToPO   = CAST(AVG(CAST(l.DaysToPO AS DECIMAL(9,2))) AS DECIMAL(9,1)),
           FollowUpDue   = (SELECT COUNT(*) FROM dbo.v_Qt_FollowUpDue d WHERE ISNULL(d.ControlBy,N'') = ISNULL(l.ControlBy,N''))
    FROM dbo.v_Qt_QuotationList l
    WHERE l.SubmitDate BETWEEN @From AND @To AND l.QStatus NOT IN ('DRAFT','CANCELLED')
      AND (@SourceType IS NULL OR l.SourceType = @SourceType)
    GROUP BY l.ControlBy
    ORDER BY QNSent DESC;

    /* 2) รายเดือน */
    SELECT Month = FORMAT(l.SubmitDate, 'yyyy-MM'),
           WonValue  = SUM(CASE WHEN l.QStatus IN ('PO_RECEIVED','JOB_RECEIVED') THEN l.QuoPrice ELSE 0 END),
           WaitValue = SUM(CASE WHEN l.QStatus = 'WAIT_PO' THEN l.QuoPrice ELSE 0 END),
           LostValue = SUM(CASE WHEN l.QStatus = 'LOST' THEN l.QuoPrice ELSE 0 END),
           WinRatePct= CAST(100.0 * SUM(CASE WHEN l.QStatus IN ('PO_RECEIVED','JOB_RECEIVED') THEN 1 ELSE 0 END)
                            / NULLIF(SUM(CASE WHEN l.QStatus IN ('PO_RECEIVED','JOB_RECEIVED','LOST') THEN 1 ELSE 0 END), 0) AS DECIMAL(5,1))
    FROM dbo.v_Qt_QuotationList l
    WHERE l.SubmitDate BETWEEN @From AND @To AND l.QStatus NOT IN ('DRAFT','CANCELLED')
      AND (@SourceType IS NULL OR l.SourceType = @SourceType)
    GROUP BY FORMAT(l.SubmitDate, 'yyyy-MM') ORDER BY Month;

    /* 3) เหตุผลที่ไม่ได้งาน */
    SELECT l.LostReasonCode, l.LostReasonText, QNCount = COUNT(*), Value = SUM(l.QuoPrice)
    FROM dbo.v_Qt_QuotationList l
    WHERE l.QStatus = 'LOST' AND l.SubmitDate BETWEEN @From AND @To AND (@SourceType IS NULL OR l.SourceType = @SourceType)
    GROUP BY l.LostReasonCode, l.LostReasonText ORDER BY QNCount DESC;

    /* 4) อายุ QN รอ PO แยกตาม Sale (ไม่จำกัดช่วงวันที่) */
    SELECT ControlBy,
           D0_7   = SUM(CASE WHEN WaitPODays <= 7  THEN QuoPrice ELSE 0 END),
           D8_14  = SUM(CASE WHEN WaitPODays BETWEEN 8 AND 14 THEN QuoPrice ELSE 0 END),
           D15_30 = SUM(CASE WHEN WaitPODays BETWEEN 15 AND 30 THEN QuoPrice ELSE 0 END),
           D30up  = SUM(CASE WHEN WaitPODays > 30 THEN QuoPrice ELSE 0 END)
    FROM dbo.v_Qt_QuotationList
    WHERE QStatus = 'WAIT_PO' AND (@SourceType IS NULL OR SourceType = @SourceType)
    GROUP BY ControlBy;
END;
GO

/* ตัวอย่าง
   INSERT dbo.Sys_UserRole (LoginName, RoleCode) VALUES (N'DOMAIN\salesmgr', 'SALES_MGR'), (N'DOMAIN\gm', 'GM'), (N'DOMAIN\md', 'MD');
   EXEC dbo.sp_Qt_SalesDashboard @From = '2026-08-01', @To = '2026-11-19';
   EXEC dbo.sp_Qt_AddFollowUp @QNNo = N'QN12858/26', @ContactDate = '2026-11-19', @Channel = 'PHONE', @ResultCode = 'BUDGET_WAIT', @NextFollowDate = '2026-11-26';
   SELECT * FROM dbo.v_Qt_FollowUpDue ORDER BY ControlBy, AgeDays DESC;
   EXEC dbo.sp_Qt_SendFollowUpMail @PreviewOnly = 1;
   EXEC dbo.sp_Qt_PrintData @QNNo = N'QN12857/26';
*/
