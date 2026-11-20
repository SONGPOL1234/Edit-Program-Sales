/* =====================================================================
   Status Checking : ติดตามสถานะเครื่องรายตัว (SQL Server 2016+)
   ---------------------------------------------------------------------
   แนวคิด
   - 1 แถว = เครื่อง 1 ตัว (Cal ID) ต่อการรับเข้า 1 รอบ (Receive No.)
   - สถานะ "ไม่ต้องกด Update" : คำนวณจากวันที่ของเอกสารแต่ละขั้น
       RECV → INLAB (เปิด WO) → CAL (สอบเทียบ) → CERT (ออก Cert) → RETURNED (ส่งคืน)
       → INVOICED (ออก Invoice) → PAID (ออกใบกำกับ/รับเงิน RV)
   - เก็บได้เฉพาะ "พักงาน" และหมายเหตุ ที่คนกรอกเอง
   - เชื่อมกับ Recall (Rc_*) และ Quotation (Qt_*) ด้วย Cal ID / RN / QN
   หมายเหตุ: ชื่อตารางต้นทาง (รับเครื่อง, WO, Cert, Invoice, RV) ในระบบเดิมยังไม่ทราบ
             ส่วน sp_St_SyncFromSources ใส่ชื่อสมมติไว้ ต้อง map ให้ตรงก่อนใช้งานจริง
   ===================================================================== */
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
GO

/* ---------- 1) ตารางหลัก ---------- */
IF OBJECT_ID('dbo.St_HoldReason') IS NULL
BEGIN
    CREATE TABLE dbo.St_HoldReason (HoldCode VARCHAR(20) PRIMARY KEY, HoldText NVARCHAR(100) NOT NULL, SortNo INT NOT NULL DEFAULT 0, IsActive BIT NOT NULL DEFAULT 1);
    INSERT dbo.St_HoldReason (HoldCode, HoldText, SortNo) VALUES
      ('PARTS',    N'รออะไหล่/ซ่อม', 1),
      ('CUST_OK',  N'รอลูกค้ายืนยันซ่อม', 2),
      ('SUBCON',   N'ส่ง Sub-contract', 3),
      ('STANDARD', N'รอ Standard กลับจากสอบเทียบ', 4),
      ('CUST_INFO',N'รอข้อมูลจากลูกค้า', 5);
END;
GO

IF OBJECT_ID('dbo.St_ItemTrack') IS NULL
CREATE TABLE dbo.St_ItemTrack (
    TrackID        INT IDENTITY PRIMARY KEY,
    CalID          NVARCHAR(50)  NOT NULL,
    ReceiveNo      NVARCHAR(30)  NOT NULL,                 -- RN08023/26
    CustomerID     NVARCHAR(20)  NULL,
    CustomerName   NVARCHAR(255) NULL,
    CertName       NVARCHAR(255) NULL,                     -- Certificate Name
    Description    NVARCHAR(255) NULL,
    Model          NVARCHAR(100) NULL,
    Manufacturer   NVARCHAR(100) NULL,
    SerialNo       NVARCHAR(100) NULL,
    AssetNo        NVARCHAR(100) NULL,
    ServiceType    NVARCHAR(50)  NULL,                     -- Electrical / Dimension / Pressure ...
    ControlBy      NVARCHAR(100) NULL,
    CustomerReqNo  NVARCHAR(30)   NULL,                    -- Customer Request No.
    QNNo           NVARCHAR(30)  NULL,
    UnitPrice      DECIMAL(18,2) NULL,
    ReceivedDate   DATE          NOT NULL,
    WONo           NVARCHAR(30)  NULL,  WODate      DATE NULL,
    CalDate        DATE          NULL,
    CertNo         NVARCHAR(30)  NULL,  CertDate    DATE NULL,
    ReturnedDate   DATE          NULL,                     -- ส่งคืนลูกค้า / ลูกค้ารับเครื่อง
    InvoiceNo      NVARCHAR(30)  NULL,  InvoiceDate DATE NULL,
    TaxInvoiceNo   NVARCHAR(30)  NULL,  TaxInvoiceDate DATE NULL,   -- RV
    HoldCode       VARCHAR(20)   NULL REFERENCES dbo.St_HoldReason(HoldCode),
    Remarks        NVARCHAR(1000) NULL,
    UpdatedBy      NVARCHAR(100) NULL,
    UpdatedAt      DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    StatusCode AS CAST(CASE WHEN TaxInvoiceNo IS NOT NULL THEN 'PAID'
                            WHEN InvoiceNo    IS NOT NULL THEN 'INVOICED'
                            WHEN ReturnedDate IS NOT NULL THEN 'RETURNED'
                            WHEN CertDate     IS NOT NULL THEN 'CERT'
                            WHEN CalDate      IS NOT NULL THEN 'CAL'
                            WHEN WONo         IS NOT NULL THEN 'INLAB'
                            ELSE 'RECV' END AS VARCHAR(10)) PERSISTED,
    CONSTRAINT UQ_St_Item UNIQUE (CalID, ReceiveNo)
);
GO
/* ดัชนีสำหรับช่องค้นหาเดียว (ค้นได้ทุกเลข) */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_St_Cust')     CREATE INDEX IX_St_Cust     ON dbo.St_ItemTrack (CustomerID, ReceivedDate DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_St_Status')   CREATE INDEX IX_St_Status   ON dbo.St_ItemTrack (StatusCode, ReceivedDate);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_St_Serial')   CREATE INDEX IX_St_Serial   ON dbo.St_ItemTrack (SerialNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_St_QN')       CREATE INDEX IX_St_QN       ON dbo.St_ItemTrack (QNNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_St_Cert')     CREATE INDEX IX_St_Cert     ON dbo.St_ItemTrack (CertNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_St_Inv')      CREATE INDEX IX_St_Inv      ON dbo.St_ItemTrack (InvoiceNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_St_RN')       CREATE INDEX IX_St_RN       ON dbo.St_ItemTrack (ReceiveNo);
GO

/* ตั้งค่า : เป้า Turnaround (วัน) และเกณฑ์ติดตามการชำระ */
IF OBJECT_ID('dbo.St_Setting') IS NULL
BEGIN
    CREATE TABLE dbo.St_Setting (SettingID TINYINT PRIMARY KEY DEFAULT 1 CHECK (SettingID = 1), TatTargetDays INT NOT NULL DEFAULT 14, PayFollowDays INT NOT NULL DEFAULT 30);
    INSERT dbo.St_Setting DEFAULT VALUES;
END;
GO

/* ---------- 2) View หลัก : สถานะ + ตัวชี้งานค้าง ---------- */
CREATE OR ALTER VIEW dbo.v_St_Status
AS
SELECT t.*,
       StatusText = CASE t.StatusCode WHEN 'RECV' THEN N'รับเครื่องแล้ว' WHEN 'INLAB' THEN N'กำลังสอบเทียบ' WHEN 'CAL' THEN N'สอบเทียบเสร็จ'
                         WHEN 'CERT' THEN N'ออก Cert แล้ว' WHEN 'RETURNED' THEN N'ส่งคืนแล้ว' WHEN 'INVOICED' THEN N'ออก Invoice แล้ว' ELSE N'รับชำระแล้ว (RV)' END,
       HoldText   = h.HoldText,
       TatDays    = DATEDIFF(DAY, t.ReceivedDate, ISNULL(t.CertDate, CAST(GETDATE() AS DATE))),     -- รับ → ออก Cert (หรือถึงวันนี้)
       IsInLab    = CAST(CASE WHEN t.ReturnedDate IS NULL THEN 1 ELSE 0 END AS BIT),
       IsLate     = CAST(CASE WHEN t.CertDate IS NULL AND DATEDIFF(DAY, t.ReceivedDate, GETDATE()) > s.TatTargetDays THEN 1 ELSE 0 END AS BIT),
       IsOnHold   = CAST(CASE WHEN t.ReturnedDate IS NULL AND t.HoldCode IS NOT NULL THEN 1 ELSE 0 END AS BIT),
       WaitReturn = CAST(CASE WHEN t.CertDate IS NOT NULL AND t.ReturnedDate IS NULL THEN 1 ELSE 0 END AS BIT),
       WaitInvoice= CAST(CASE WHEN t.ReturnedDate IS NOT NULL AND t.InvoiceNo IS NULL THEN 1 ELSE 0 END AS BIT),
       WaitPay    = CAST(CASE WHEN t.InvoiceNo IS NOT NULL AND t.TaxInvoiceNo IS NULL AND DATEDIFF(DAY, t.InvoiceDate, GETDATE()) > s.PayFollowDays THEN 1 ELSE 0 END AS BIT),
       IsLatest   = CAST(CASE WHEN ROW_NUMBER() OVER (PARTITION BY t.CalID ORDER BY t.ReceivedDate DESC, t.TrackID DESC) = 1 THEN 1 ELSE 0 END AS BIT)
FROM dbo.St_ItemTrack t
CROSS JOIN dbo.St_Setting s
LEFT JOIN dbo.St_HoldReason h ON h.HoldCode = t.HoldCode;
GO

/* ---------- 3) ค้นหา : ช่องเดียวค้นได้ทุกเลข + ตัวกรอง + มุมมองงานค้าง ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_St_Search
    @Keyword      NVARCHAR(50)  = NULL,   -- Cal ID / Serial / Asset / RN / WO / QN / Cert / Invoice / RV / Customer Req. No.
    @Customer     NVARCHAR(255) = NULL,   -- Customer ID หรือบางส่วนของชื่อ
    @Year         INT           = NULL,   -- ปีที่รับเครื่อง
    @ServiceType  NVARCHAR(50)  = NULL,
    @ControlBy    NVARCHAR(100) = NULL,
    @DescText     NVARCHAR(100) = NULL,
    @StatusList   VARCHAR(100)  = NULL,   -- 'RECV,INLAB,CAL'
    @View         VARCHAR(10)   = 'ALL',  -- ALL / INLAB / LATE / HOLD / WAITRET / WAITINV / WAITPAY
    @LatestOnly   BIT           = 1,      -- แสดงเฉพาะรอบล่าสุดของแต่ละเครื่อง (ไม่ใช้เมื่อมี @Keyword)
    @NoCertOnly   BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k NVARCHAR(52) = N'%' + NULLIF(LTRIM(RTRIM(@Keyword)), N'') + N'%';
    SELECT TOP (5000) v.*
    FROM dbo.v_St_Status v
    WHERE (@k IS NULL OR v.CalID LIKE @k OR v.SerialNo LIKE @k OR v.AssetNo LIKE @k OR v.ReceiveNo LIKE @k OR v.WONo LIKE @k OR v.QNNo LIKE @k
                      OR v.CertNo LIKE @k OR v.InvoiceNo LIKE @k OR v.TaxInvoiceNo LIKE @k OR v.CustomerReqNo LIKE @k)
      AND (@LatestOnly = 0 OR @k IS NOT NULL OR v.IsLatest = 1)
      AND (@Customer IS NULL OR v.CustomerID = @Customer OR v.CustomerName LIKE N'%' + @Customer + N'%')
      AND (@Year IS NULL OR YEAR(v.ReceivedDate) = @Year)
      AND (@ServiceType IS NULL OR v.ServiceType = @ServiceType)
      AND (@ControlBy IS NULL OR v.ControlBy = @ControlBy)
      AND (@DescText IS NULL OR v.Description LIKE N'%' + @DescText + N'%' OR v.Model LIKE N'%' + @DescText + N'%' OR v.Manufacturer LIKE N'%' + @DescText + N'%')
      AND (@StatusList IS NULL OR v.StatusCode IN (SELECT value FROM STRING_SPLIT(@StatusList, ',')))
      AND (@NoCertOnly = 0 OR v.CertDate IS NULL)
      AND (@View = 'ALL'
           OR (@View = 'INLAB'   AND v.IsInLab = 1)
           OR (@View = 'LATE'    AND v.IsLate = 1)
           OR (@View = 'HOLD'    AND v.IsOnHold = 1)
           OR (@View = 'WAITRET' AND v.WaitReturn = 1)
           OR (@View = 'WAITINV' AND v.WaitInvoice = 1)
           OR (@View = 'WAITPAY' AND v.WaitPay = 1))
    ORDER BY v.ReceivedDate DESC, v.CalID;
END;
GO

/* ตัวเลขบนการ์ดงานค้าง */
CREATE OR ALTER PROCEDURE dbo.sp_St_Backlog
AS
BEGIN
    SET NOCOUNT ON;
    SELECT InLab       = SUM(CAST(IsInLab AS INT)),
           Late        = SUM(CAST(IsLate AS INT)),
           OnHold      = SUM(CAST(IsOnHold AS INT)),
           WaitReturn  = SUM(CAST(WaitReturn AS INT)),
           WaitInvoice = SUM(CAST(WaitInvoice AS INT)),
           WaitPay     = SUM(CAST(WaitPay AS INT))
    FROM dbo.v_St_Status;
END;
GO

/* รายละเอียดเครื่อง : (1) ทุกรอบของ Cal ID  (2) ไทม์ไลน์ของรอบที่เลือก */
CREATE OR ALTER PROCEDURE dbo.sp_St_Timeline @CalID NVARCHAR(50), @ReceiveNo NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.v_St_Status WHERE CalID = @CalID ORDER BY ReceivedDate DESC;

    SELECT TOP (1) @ReceiveNo = ISNULL(@ReceiveNo, ReceiveNo) FROM dbo.St_ItemTrack WHERE CalID = @CalID ORDER BY ReceivedDate DESC;
    SELECT s.StepNo, s.StepName, s.StepDate, s.DocNo
    FROM dbo.St_ItemTrack t
    CROSS APPLY (VALUES (1, N'รับเครื่อง', t.ReceivedDate, t.ReceiveNo), (2, N'เปิด WO', t.WODate, t.WONo), (3, N'สอบเทียบ', t.CalDate, NULL),
                        (4, N'ออก Cert', t.CertDate, t.CertNo), (5, N'ส่งคืนลูกค้า', t.ReturnedDate, NULL),
                        (6, N'ออก Invoice', t.InvoiceDate, t.InvoiceNo), (7, N'ใบกำกับ/รับเงิน', t.TaxInvoiceDate, t.TaxInvoiceNo)) s(StepNo, StepName, StepDate, DocNo)
    WHERE t.CalID = @CalID AND t.ReceiveNo = @ReceiveNo
    ORDER BY s.StepNo;
END;
GO

/* พักงาน / หมายเหตุ : สิ่งเดียวที่คนแก้เอง */
CREATE OR ALTER PROCEDURE dbo.sp_St_SetHold @CalID NVARCHAR(50), @ReceiveNo NVARCHAR(30), @HoldCode VARCHAR(20) = NULL, @Remarks NVARCHAR(1000) = NULL, @UserName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.St_ItemTrack SET HoldCode = NULLIF(@HoldCode, ''), Remarks = @Remarks, UpdatedBy = @UserName, UpdatedAt = SYSDATETIME()
    WHERE CalID = @CalID AND ReceiveNo = @ReceiveNo;
END;
GO

/* ---------- 4) ดึงข้อมูลจากระบบงานเดิม (รันทุก 5-15 นาทีด้วย SQL Agent หรือเรียกจาก trigger ของแต่ละขั้น) ----------
   !! ชื่อตาราง/คอลัมน์ต้นทางด้านล่างเป็นชื่อสมมติ ให้แก้ตามฐานข้อมูลจริง !!
     Lab_ReceiveItem (รับเครื่อง)   : CalID, ReceiveNo, ReceiveDate, CustomerID, CustReqNo, QNNo ...
     Lab_WorkOrder   (WO)          : CalID, ReceiveNo, WONo, WODate
     Lab_Certificate (Cert)        : CalID, ReceiveNo, CertNo, CalDate, IssueDate, ReturnDate
     Acc_InvoiceItem (Invoice)     : ReceiveNo, CalID, InvoiceNo, InvoiceDate
     Acc_TaxInvoice  (RV)          : InvoiceNo, TaxInvoiceNo, TaxInvoiceDate
   ------------------------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.sp_St_SyncFromSources @SinceDays INT = 120
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @since DATE = DATEADD(DAY, -@SinceDays, CAST(GETDATE() AS DATE));

    MERGE dbo.St_ItemTrack AS t
    USING (
        SELECT r.CalID, r.ReceiveNo, r.ReceiveDate, r.CustomerID, c.CustomerName, r.CertName, e.Description, e.Model, e.Manuf, e.SerialNo, e.AssetNo,
               e.ServiceType, ControlBy = c.SaleName, r.CustReqNo, r.QNNo, r.UnitPrice,
               w.WONo, w.WODate, ce.CalDate, ce.CertNo, ce.IssueDate, ce.ReturnDate, iv.InvoiceNo, iv.InvoiceDate, tx.TaxInvoiceNo, tx.TaxInvoiceDate
        FROM dbo.Lab_ReceiveItem r
        LEFT JOIN dbo.Rc_Equipment e ON e.CalID = r.CalID
        LEFT JOIN dbo.Rc_Customer  c ON c.CustomerID = r.CustomerID
        OUTER APPLY (SELECT TOP (1) WONo, WODate FROM dbo.Lab_WorkOrder w WHERE w.CalID = r.CalID AND w.ReceiveNo = r.ReceiveNo ORDER BY WODate) w
        OUTER APPLY (SELECT TOP (1) CertNo, CalDate, IssueDate, ReturnDate FROM dbo.Lab_Certificate x WHERE x.CalID = r.CalID AND x.ReceiveNo = r.ReceiveNo ORDER BY IssueDate DESC) ce
        OUTER APPLY (SELECT TOP (1) InvoiceNo, InvoiceDate FROM dbo.Acc_InvoiceItem i WHERE i.CalID = r.CalID AND i.ReceiveNo = r.ReceiveNo ORDER BY InvoiceDate DESC) iv
        OUTER APPLY (SELECT TOP (1) TaxInvoiceNo, TaxInvoiceDate FROM dbo.Acc_TaxInvoice x WHERE x.InvoiceNo = iv.InvoiceNo ORDER BY TaxInvoiceDate DESC) tx
        WHERE r.ReceiveDate >= @since
    ) AS s
    ON t.CalID = s.CalID AND t.ReceiveNo = s.ReceiveNo
    WHEN MATCHED THEN UPDATE SET
        CustomerID = s.CustomerID, CustomerName = s.CustomerName, CertName = s.CertName, Description = s.Description, Model = s.Model, Manufacturer = s.Manuf,
        SerialNo = s.SerialNo, AssetNo = s.AssetNo, ServiceType = s.ServiceType, ControlBy = s.ControlBy, CustomerReqNo = s.CustReqNo, QNNo = s.QNNo, UnitPrice = s.UnitPrice,
        ReceivedDate = s.ReceiveDate, WONo = s.WONo, WODate = s.WODate, CalDate = s.CalDate, CertNo = s.CertNo, CertDate = s.IssueDate, ReturnedDate = s.ReturnDate,
        InvoiceNo = s.InvoiceNo, InvoiceDate = s.InvoiceDate, TaxInvoiceNo = s.TaxInvoiceNo, TaxInvoiceDate = s.TaxInvoiceDate, UpdatedAt = SYSDATETIME(),
        HoldCode = CASE WHEN s.ReturnDate IS NOT NULL THEN NULL ELSE t.HoldCode END          -- ส่งคืนแล้วล้างพักงานอัตโนมัติ
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (CalID, ReceiveNo, CustomerID, CustomerName, CertName, Description, Model, Manufacturer, SerialNo, AssetNo, ServiceType, ControlBy, CustomerReqNo, QNNo, UnitPrice,
         ReceivedDate, WONo, WODate, CalDate, CertNo, CertDate, ReturnedDate, InvoiceNo, InvoiceDate, TaxInvoiceNo, TaxInvoiceDate)
        VALUES (s.CalID, s.ReceiveNo, s.CustomerID, s.CustomerName, s.CertName, s.Description, s.Model, s.Manuf, s.SerialNo, s.AssetNo, s.ServiceType, s.ControlBy, s.CustReqNo, s.QNNo, s.UnitPrice,
         s.ReceiveDate, s.WONo, s.WODate, s.CalDate, s.CertNo, s.IssueDate, s.ReturnDate, s.InvoiceNo, s.InvoiceDate, s.TaxInvoiceNo, s.TaxInvoiceDate);

    /* ออก Cert แล้ว → แจ้ง Recall/Quotation ให้ตั้งรอบถัดไป (ใช้ proc เดิมจาก Quotation_List.sql) */
    IF OBJECT_ID('dbo.sp_Qt_SyncFromCalEvent') IS NOT NULL
        EXEC dbo.sp_Qt_SyncFromCalEvent;
END;
GO

/* ---------- 5) ย้ายข้อมูลเก่าครั้งแรก (60,698 แถวในหน้าเดิม) : รัน sp_St_SyncFromSources @SinceDays = 4000 ครั้งเดียว ---------- */

/* ตัวอย่างการใช้
   EXEC dbo.sp_St_Search @Keyword = N'SEAL00002';
   EXEC dbo.sp_St_Search @View = 'LATE';
   EXEC dbo.sp_St_Search @Customer = N'CUS02532', @Year = 2026, @StatusList = 'RECV,INLAB,CAL';
   EXEC dbo.sp_St_Backlog;
   EXEC dbo.sp_St_Timeline @CalID = N'SEAL00002';
   EXEC dbo.sp_St_SetHold @CalID = N'SEAL00002', @ReceiveNo = N'RN08023/26', @HoldCode = 'PARTS', @UserName = N'lab01';
*/
