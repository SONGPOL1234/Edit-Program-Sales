/* =====================================================================
   ระบบ Calibration Recall (ออกแบบใหม่)  -  SQL Server 2016 SP1 ขึ้นไป (ใช้ CREATE OR ALTER, STRING_SPLIT ต้อง compatibility level 130)
   ---------------------------------------------------------------------
   แนวคิดหลัก
   1) Recall ต่อ "เครื่อง" (Equipment) ไม่ใช่ต่อ RN
      - Cal. ID ขึ้นต้น PCAL = รหัสเครื่องที่แล็บออกให้ ใช้เป็นตัวระบุเครื่องได้เลย
        (แม้ชื่อลูกค้าจะเปลี่ยน/สะกดต่างกัน เช่น ไทย/อังกฤษ)
      - Cal. ID อื่น (PT00001, LAB587 ...) ไม่ unique  ใช้ CalID + Serial + ลูกค้า แทน
   2) เก็บประวัติสอบเทียบทุกครั้ง (Rc_CalEvent) แล้ว Recall จาก "ครั้งล่าสุด" ของแต่ละเครื่องเท่านั้น
   3) ราคา Quo. Cost เก็บครั้งเดียวต่อ QN (Rc_Quotation) แล้วกระจายเป็นราคาต่อรายการ
      ยอดรวมจึงบวกกันได้ทุกระดับ ไม่ซ้ำ x2 / x3 แบบหน้าจอเดิม
   4) Rc_RecallTask = งานติดตาม 1 แถว ต่อ 1 เครื่อง ต่อ 1 รอบ Due
      สถานะ OPEN -> NOTIFIED -> QUOTED -> ACCEPTED -> SCHEDULED -> RECEIVED  (หรือ OVERDUE / CANCELLED)
      ระบบปิดงานเป็น RECEIVED ให้อัตโนมัติเมื่อพบการสอบเทียบครั้งใหม่ของเครื่องนั้น
   5) Due Date คำนวณจากที่เดียว: DATEADD(MONTH, IntervalMonth, CalDate) [- 1 วัน ถ้า DueRule='P']

   ลำดับการใช้งาน
     (1) นำเข้าชีต "Recall Detail" จาก Excel ลง dbo.stg_RecallDetail
     (2) EXEC dbo.sp_Rc_LoadFromStaging
     (3) EXEC dbo.sp_Rc_RunDaily @AsOf = '2026-11-19'    -- ตั้ง SQL Agent Job ให้รันทุกวัน
     (4) หน้าจอใช้ dbo.sp_Rc_RecallScreen / v_Rc_RecallList / v_Rc_RecallHeader

   หมายเหตุ: ชื่อตารางขึ้นต้น Rc_ เพื่อไม่ชนกับตารางเดิม  ถ้าระบบจริงมีตาราง RN / QN / Item อยู่แล้ว
   ให้เปลี่ยน sp_Rc_LoadFromStaging ไปอ่านจากตารางจริงแทน stg_RecallDetail
   ===================================================================== */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   0) STAGING : โครงสร้างตรงกับชีต "Recall Detail" (19 คอลัมน์)
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.stg_RecallDetail') IS NULL
CREATE TABLE dbo.stg_RecallDetail (
    ReceiveNo     NVARCHAR(30),
    RecDate       NVARCHAR(30),
    SenderName    NVARCHAR(255),
    EndUserName   NVARCHAR(255),
    SaleName      NVARCHAR(100),
    Status        NVARCHAR(50),
    QNNo          NVARCHAR(30),
    Qty           NVARCHAR(50),
    QuoCost       NVARCHAR(50),
    CalID         NVARCHAR(50),
    Description   NVARCHAR(255),
    Model         NVARCHAR(100),
    Manuf         NVARCHAR(100),
    SerialNo      NVARCHAR(100),
    CertNo        NVARCHAR(30),
    CalDate       NVARCHAR(30),      -- ใน Excel เป็นข้อความ dd/mm/yyyy
    DueDate       NVARCHAR(30),
    RecallMonth   NVARCHAR(10),
    NewQNNo       NVARCHAR(30),
    SourceFile    NVARCHAR(100) NULL
);
GO

/* ---------------------------------------------------------------------
   1) MASTER : เครื่องมือของลูกค้า
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Rc_Equipment') IS NULL
CREATE TABLE dbo.Rc_Equipment (
    EquipmentID    INT IDENTITY(1,1) PRIMARY KEY,
    EquipKey       NVARCHAR(400) NOT NULL,          -- PCALxxxx  หรือ  CalID|Serial|EndUser
    CalID          NVARCHAR(50)  NOT NULL,
    SerialNo       NVARCHAR(100) NULL,
    CustomerID     NVARCHAR(20)  NULL,              -- รหัสลูกค้าจากตารางลูกค้าในระบบเดิม
    EndUserName    NVARCHAR(255) NOT NULL,          -- ชื่อล่าสุด
    SenderName     NVARCHAR(255) NULL,
    Description    NVARCHAR(255) NULL,
    Model          NVARCHAR(100) NULL,
    Manuf          NVARCHAR(100) NULL,
    SaleName       NVARCHAR(100) NULL,              -- ผู้ดูแลล่าสุด
    IntervalMonth  TINYINT       NOT NULL DEFAULT 12,   -- รอบสอบเทียบ 6/12/24/36
    DueRule        CHAR(1)       NOT NULL DEFAULT 'S',  -- S = วันเดียวกัน, P = ก่อนหนึ่งวัน
    IsWeakKey      BIT           NOT NULL DEFAULT 0,    -- 1 = Cal ID ไม่ใช่ PCAL ควรตรวจสอบ
    IsActive       BIT           NOT NULL DEFAULT 1,    -- 0 = เลิกใช้/ขายแล้ว ไม่ต้อง recall
    InactiveReason NVARCHAR(255) NULL,
    CONSTRAINT UQ_Rc_Equipment_Key UNIQUE (EquipKey)
);
GO

/* ---------------------------------------------------------------------
   2) ใบเสนอราคา : 1 แถวต่อ QN  (แก้ปัญหายอดซ้ำ)
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Rc_Quotation') IS NULL
CREATE TABLE dbo.Rc_Quotation (
    QNNo       NVARCHAR(30) PRIMARY KEY,
    QuoCost    DECIMAL(18,2) NOT NULL DEFAULT 0,
    ItemCount  INT NOT NULL DEFAULT 0              -- จำนวนรายการที่อยู่ใต้ QN นี้ (ใช้กระจายราคา)
);
GO

/* ---------------------------------------------------------------------
   3) ประวัติการสอบเทียบ : 1 แถวต่อ 1 ใบ Cert
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Rc_CalEvent') IS NULL
BEGIN
CREATE TABLE dbo.Rc_CalEvent (
    CalEventID   INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentID  INT NOT NULL REFERENCES dbo.Rc_Equipment(EquipmentID),
    ReceiveNo    NVARCHAR(30)  NOT NULL,
    RecDate      DATE          NULL,
    CalDate      DATE          NOT NULL,
    DueDate      DATE          NOT NULL,
    CertNo       NVARCHAR(30)  NOT NULL,
    QNNo         NVARCHAR(30)  NULL,
    Status       NVARCHAR(50)  NULL,                -- IN-LAB / ON-SITE / SUB-CONT
    SaleName     NVARCHAR(100) NULL,
    ItemPrice    DECIMAL(18,2) NULL,                -- ราคาจริงต่อรายการ (ถ้ามีจากใบเสนอราคา)
    ItemPriceEst DECIMAL(18,2) NULL,                -- ประมาณการ = QuoCost / ItemCount ของ QN
    CONSTRAINT UQ_Rc_CalEvent UNIQUE (EquipmentID, CertNo)
);
CREATE INDEX IX_Rc_CalEvent_Equip ON dbo.Rc_CalEvent(EquipmentID, CalDate DESC) INCLUDE (DueDate);
END;
GO

/* ---------------------------------------------------------------------
   4) งาน Recall : 1 แถวต่อ 1 เครื่อง ต่อ 1 รอบ Due
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Rc_RecallTask') IS NULL
BEGIN
CREATE TABLE dbo.Rc_RecallTask (
    RecallID          INT IDENTITY(1,1) PRIMARY KEY,
    EquipmentID       INT  NOT NULL REFERENCES dbo.Rc_Equipment(EquipmentID),
    SourceCalEventID  INT  NOT NULL REFERENCES dbo.Rc_CalEvent(CalEventID),  -- ครั้งที่ทำให้ครบกำหนด
    DueDate           DATE NOT NULL,
    RecallMonth       AS CONVERT(CHAR(7), DueDate, 126) PERSISTED,         -- 'YYYY-MM'
    RecallStatus      VARCHAR(12) NOT NULL DEFAULT 'OPEN'
        CONSTRAINT CK_Rc_RecallTask_Status CHECK (RecallStatus IN ('OPEN','NOTIFIED','QUOTED','ACCEPTED','SCHEDULED','RECEIVED','OVERDUE','CANCELLED')),
    NotifyLevel       SMALLINT NULL,                   -- 90 / 60 / 30 / 0 วันที่แจ้งไปแล้วล่าสุด
    LastNotifyDate    DATE NULL,
    NewQNNo           NVARCHAR(30) NULL,               -- ใบเสนอราคารอบใหม่
    NewReceiveNo      NVARCHAR(30) NULL,               -- RN รอบใหม่ (ระบบเติมให้ตอน match)
    ReturnCalEventID  INT NULL REFERENCES dbo.Rc_CalEvent(CalEventID),
    Remark            NVARCHAR(500) NULL,
    CreatedAt         DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedAt         DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_Rc_RecallTask UNIQUE (EquipmentID, DueDate)
);
CREATE INDEX IX_Rc_RecallTask_Due ON dbo.Rc_RecallTask(DueDate, RecallStatus);
END;
GO

/* ถ้าสร้าง Rc_Equipment ไปก่อนแล้ว ให้เพิ่มคอลัมน์ CustomerID */
IF COL_LENGTH('dbo.Rc_Equipment','CustomerID') IS NULL
    ALTER TABLE dbo.Rc_Equipment ADD CustomerID NVARCHAR(20) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Rc_Equipment_Customer')
    CREATE INDEX IX_Rc_Equipment_Customer ON dbo.Rc_Equipment(CustomerID);
GO

/* =====================================================================
   FUNCTION : คำนวณ Due Date (ใช้ที่เดียวทั้งระบบ)
   ===================================================================== */
CREATE OR ALTER FUNCTION dbo.fn_Rc_DueDate (@CalDate DATE, @IntervalMonth TINYINT, @DueRule CHAR(1))
RETURNS DATE
AS
BEGIN
    RETURN DATEADD(DAY, CASE WHEN @DueRule = 'P' THEN -1 ELSE 0 END,
                   DATEADD(MONTH, @IntervalMonth, @CalDate));
END;
GO

/* =====================================================================
   PROC 1 : โหลดจาก staging -> Equipment / Quotation / CalEvent
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_LoadFromStaging
AS
BEGIN
    SET NOCOUNT ON;

    /* ทำความสะอาด + แปลงชนิดข้อมูล */
    IF OBJECT_ID('tempdb..#raw') IS NOT NULL DROP TABLE #raw;
    SELECT
        ReceiveNo   = LTRIM(RTRIM(s.ReceiveNo)),
        RecDate     = COALESCE(TRY_CONVERT(DATE, s.RecDate, 103), TRY_CONVERT(DATE, s.RecDate, 120)),
        SenderName  = LTRIM(RTRIM(s.SenderName)),
        EndUserName = LTRIM(RTRIM(s.EndUserName)),
        SaleName    = LTRIM(RTRIM(s.SaleName)),
        Status      = LTRIM(RTRIM(s.Status)),
        QNNo        = NULLIF(LTRIM(RTRIM(s.QNNo)), ''),
        QuoCost     = TRY_CONVERT(DECIMAL(18,2), s.QuoCost),
        CalID       = UPPER(LTRIM(RTRIM(s.CalID))),
        SerialNo    = NULLIF(NULLIF(NULLIF(LTRIM(RTRIM(s.SerialNo)), ''), '-'), 'N/A'),
        s.Description, s.Model, s.Manuf,
        CertNo      = NULLIF(LTRIM(RTRIM(s.CertNo)), ''),
        CalDate     = COALESCE(TRY_CONVERT(DATE, s.CalDate, 103), TRY_CONVERT(DATE, s.CalDate, 120)),
        DueDate     = COALESCE(TRY_CONVERT(DATE, s.DueDate, 103), TRY_CONVERT(DATE, s.DueDate, 120))
    INTO #raw
    FROM dbo.stg_RecallDetail s
    WHERE NULLIF(LTRIM(RTRIM(s.CalID)), '') IS NOT NULL;

    IF OBJECT_ID('tempdb..#src') IS NOT NULL DROP TABLE #src;
    SELECT r.ReceiveNo, r.RecDate, r.SenderName, r.EndUserName, r.SaleName, r.Status, r.QNNo, r.QuoCost,
           r.CalID, r.SerialNo, r.Description, r.Model, r.Manuf, r.CalDate, r.DueDate,
           CertNo    = ISNULL(r.CertNo, r.ReceiveNo + '|' + CONVERT(CHAR(10), r.CalDate, 120)),
           IsWeakKey = CAST(CASE WHEN r.CalID LIKE 'PCAL[0-9]%' THEN 0 ELSE 1 END AS BIT),
           EquipKey  = CAST(CASE WHEN r.CalID LIKE 'PCAL[0-9]%' THEN r.CalID
                                 ELSE LEFT(r.CalID + '|' + ISNULL(UPPER(r.SerialNo), '') + '|' + UPPER(r.EndUserName), 400)
                            END AS NVARCHAR(400)),
           iv.IntervalMonth,
           /* Due เดิม = Cal + รอบ - 1 วัน หรือไม่ */
           DueRule   = CAST(CASE WHEN r.DueDate = DATEADD(DAY, -1, DATEADD(MONTH, iv.IntervalMonth, r.CalDate))
                                 THEN 'P' ELSE 'S' END AS CHAR(1))
    INTO #src
    FROM #raw r
    /* เดารอบสอบเทียบจาก Cal -> Due ของข้อมูลเดิม (6/12/24/36 เดือน) */
    CROSS APPLY (SELECT IntervalMonth = CAST(CASE
            WHEN DATEDIFF(DAY, r.CalDate, r.DueDate) BETWEEN 150 AND 200   THEN 6
            WHEN DATEDIFF(DAY, r.CalDate, r.DueDate) BETWEEN 600 AND 800   THEN 24
            WHEN DATEDIFF(DAY, r.CalDate, r.DueDate) BETWEEN 1000 AND 1150 THEN 36
            ELSE 12 END AS TINYINT)) iv;

    /* Equipment : ใช้ข้อมูลจากครั้งล่าสุดของเครื่องนั้น */
    ;WITH lastRow AS (
        SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY EquipKey ORDER BY CalDate DESC, ReceiveNo DESC)
        FROM #src WHERE CalDate IS NOT NULL
    )
    MERGE dbo.Rc_Equipment AS t
    USING (SELECT * FROM lastRow WHERE rn = 1) AS s
       ON t.EquipKey = s.EquipKey
    WHEN MATCHED THEN UPDATE SET
         t.EndUserName = s.EndUserName, t.SenderName = s.SenderName, t.SerialNo = s.SerialNo,
         t.Description = s.Description, t.Model = s.Model, t.Manuf = s.Manuf,
         t.SaleName = s.SaleName, t.IntervalMonth = s.IntervalMonth, t.DueRule = s.DueRule
    WHEN NOT MATCHED THEN INSERT
         (EquipKey, CalID, SerialNo, EndUserName, SenderName, Description, Model, Manuf,
          SaleName, IntervalMonth, DueRule, IsWeakKey)
         VALUES (s.EquipKey, s.CalID, s.SerialNo, s.EndUserName, s.SenderName, s.Description, s.Model, s.Manuf,
          s.SaleName, s.IntervalMonth, s.DueRule, s.IsWeakKey);

    /* Quotation : 1 แถวต่อ QN */
    MERGE dbo.Rc_Quotation AS t
    USING (SELECT QNNo, QuoCost = MAX(QuoCost) FROM #src WHERE QNNo IS NOT NULL GROUP BY QNNo) AS s
       ON t.QNNo = s.QNNo
    WHEN MATCHED THEN UPDATE SET t.QuoCost = ISNULL(s.QuoCost, 0)
    WHEN NOT MATCHED THEN INSERT (QNNo, QuoCost) VALUES (s.QNNo, ISNULL(s.QuoCost, 0));

    /* CalEvent */
    INSERT dbo.Rc_CalEvent (EquipmentID, ReceiveNo, RecDate, CalDate, DueDate, CertNo, QNNo, Status, SaleName)
    SELECT e.EquipmentID, s.ReceiveNo, s.RecDate, s.CalDate,
           ISNULL(s.DueDate, dbo.fn_Rc_DueDate(s.CalDate, s.IntervalMonth, s.DueRule)),
           s.CertNo, s.QNNo, s.Status, s.SaleName
    FROM (SELECT *, d = ROW_NUMBER() OVER (PARTITION BY EquipKey, CertNo ORDER BY CalDate DESC) FROM #src) s
    JOIN dbo.Rc_Equipment e ON e.EquipKey = s.EquipKey
    WHERE s.d = 1 AND s.CalDate IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.Rc_CalEvent c WHERE c.EquipmentID = e.EquipmentID AND c.CertNo = s.CertNo);

    /* กระจายราคา QN ลงแต่ละรายการ -> ผลรวมทุกระดับเท่ากับยอด QN พอดี */
    UPDATE q SET ItemCount = x.n
    FROM dbo.Rc_Quotation q
    JOIN (SELECT QNNo, n = COUNT(*) FROM dbo.Rc_CalEvent WHERE QNNo IS NOT NULL GROUP BY QNNo) x ON x.QNNo = q.QNNo;

    UPDATE c SET ItemPriceEst = ROUND(q.QuoCost / NULLIF(q.ItemCount, 0), 2)
    FROM dbo.Rc_CalEvent c JOIN dbo.Rc_Quotation q ON q.QNNo = c.QNNo;
END;
GO

/* =====================================================================
   PROC 2 : สร้าง / อัปเดตงาน Recall  (รันทุกวัน)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_RunDaily
    @AsOf     DATE = NULL,
    @LeadDays INT  = 90          -- เปิดงาน recall ล่วงหน้ากี่วัน
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS DATE));

    /* 2.1 เปิดงานใหม่จาก "ครั้งล่าสุด" ของแต่ละเครื่องที่ใกล้ครบกำหนด */
    ;WITH lastCal AS (
        SELECT c.*, rn = ROW_NUMBER() OVER (PARTITION BY c.EquipmentID ORDER BY c.CalDate DESC, c.CalEventID DESC)
        FROM dbo.Rc_CalEvent c
    )
    INSERT dbo.Rc_RecallTask (EquipmentID, SourceCalEventID, DueDate)
    SELECT l.EquipmentID, l.CalEventID, l.DueDate
    FROM lastCal l
    JOIN dbo.Rc_Equipment e ON e.EquipmentID = l.EquipmentID AND e.IsActive = 1
    WHERE l.rn = 1
      AND l.DueDate <= DATEADD(DAY, @LeadDays, @AsOf)
      AND NOT EXISTS (SELECT 1 FROM dbo.Rc_RecallTask t
                      WHERE t.EquipmentID = l.EquipmentID AND t.DueDate = l.DueDate);

    /* 2.2 ปิดงานอัตโนมัติ: เครื่องกลับมาสอบเทียบใหม่แล้ว */
    ;WITH ret AS (
        SELECT t.RecallID, c.CalEventID, c.ReceiveNo, c.QNNo,
               rn = ROW_NUMBER() OVER (PARTITION BY t.RecallID ORDER BY c.CalDate)
        FROM dbo.Rc_RecallTask t
        JOIN dbo.Rc_CalEvent src ON src.CalEventID = t.SourceCalEventID
        JOIN dbo.Rc_CalEvent c   ON c.EquipmentID = t.EquipmentID AND c.CalDate > src.CalDate
        WHERE t.RecallStatus NOT IN ('RECEIVED','CANCELLED')
    )
    UPDATE t SET RecallStatus = 'RECEIVED', ReturnCalEventID = r.CalEventID,
                 NewReceiveNo = r.ReceiveNo, NewQNNo = ISNULL(t.NewQNNo, r.QNNo), UpdatedAt = SYSDATETIME()
    FROM dbo.Rc_RecallTask t JOIN ret r ON r.RecallID = t.RecallID AND r.rn = 1;

    /* 2.3 เกินกำหนดแล้วยังไม่กลับมา */
    UPDATE dbo.Rc_RecallTask
       SET RecallStatus = 'OVERDUE', UpdatedAt = SYSDATETIME()
     WHERE RecallStatus IN ('OPEN','NOTIFIED','QUOTED','ACCEPTED','SCHEDULED') AND DueDate < @AsOf;

    /* 2.4 ระดับการแจ้งเตือนที่ "ควร" ส่ง (90/60/30/0 วัน) -> ให้หน้าจอ/อีเมลดึงไปใช้ */
    UPDATE t SET NotifyLevel = x.lvl
    FROM dbo.Rc_RecallTask t
    CROSS APPLY (SELECT lvl = CASE
            WHEN DATEDIFF(DAY, @AsOf, t.DueDate) <= 0  THEN 0
            WHEN DATEDIFF(DAY, @AsOf, t.DueDate) <= 30 THEN 30
            WHEN DATEDIFF(DAY, @AsOf, t.DueDate) <= 60 THEN 60
            ELSE 90 END) x
    WHERE t.RecallStatus IN ('OPEN','NOTIFIED','OVERDUE')
      AND (t.NotifyLevel IS NULL OR t.NotifyLevel > x.lvl);
END;
GO

/* =====================================================================
   VIEW 1 : รายการเครื่องที่ต้อง recall (ระดับรายการ)
   ===================================================================== */
CREATE OR ALTER VIEW dbo.v_Rc_RecallList
AS
SELECT
    t.RecallID, t.RecallMonth, t.DueDate, t.RecallStatus, t.NotifyLevel, t.LastNotifyDate,
    DaysToDue   = DATEDIFF(DAY, CAST(GETDATE() AS DATE), t.DueDate),
    DueBucket   = CASE
                    WHEN t.RecallStatus IN ('RECEIVED','CANCELLED')            THEN N'ปิดแล้ว'
                    WHEN t.DueDate <  CAST(GETDATE() AS DATE)                   THEN N'เกินกำหนด'
                    WHEN DATEDIFF(DAY, CAST(GETDATE() AS DATE), t.DueDate) <= 30 THEN N'ภายใน 30 วัน'
                    WHEN DATEDIFF(DAY, CAST(GETDATE() AS DATE), t.DueDate) <= 60 THEN N'31-60 วัน'
                    ELSE N'61-90 วัน' END,
    e.EquipmentID, e.CalID, e.Description, e.Model, e.Manuf, e.SerialNo,
    e.CustomerID, e.EndUserName, e.SenderName, e.SaleName, e.IntervalMonth, e.IsWeakKey,
    LastReceiveNo = c.ReceiveNo, LastRecDate = c.RecDate, LastCalDate = c.CalDate,
    LastCertNo = c.CertNo, LastQNNo = c.QNNo, LastStatus = c.Status,
    ItemPrice  = COALESCE(c.ItemPrice, c.ItemPriceEst, 0),
    t.NewQNNo, t.NewReceiveNo, t.Remark
FROM dbo.Rc_RecallTask t
JOIN dbo.Rc_Equipment e ON e.EquipmentID = t.EquipmentID
JOIN dbo.Rc_CalEvent  c ON c.CalEventID  = t.SourceCalEventID;
GO

/* =====================================================================
   VIEW 2 : สรุประดับลูกค้า x เดือน  (แทนหน้าจอเดิมที่แสดงต่อ RN)
   ยอดเงิน = ผลรวมราคาต่อรายการ จึงไม่ซ้ำแม้หลาย RN ใช้ QN เดียวกัน
   ===================================================================== */
CREATE OR ALTER VIEW dbo.v_Rc_RecallHeader
AS
SELECT
    RecallMonth, EndUserName, SaleName,
    ItemCount     = COUNT(*),
    OpenCount     = SUM(CASE WHEN RecallStatus IN ('OPEN','NOTIFIED','QUOTED','ACCEPTED','SCHEDULED') THEN 1 ELSE 0 END),
    OverdueCount  = SUM(CASE WHEN RecallStatus = 'OVERDUE'  THEN 1 ELSE 0 END),
    ReceivedCount = SUM(CASE WHEN RecallStatus = 'RECEIVED' THEN 1 ELSE 0 END),
    FirstDue      = MIN(DueDate),
    LastDue       = MAX(DueDate),
    EstCost       = SUM(ItemPrice),
    QNList        = STUFF((SELECT DISTINCT ', ' + l2.LastQNNo
                           FROM dbo.v_Rc_RecallList l2
                           WHERE l2.RecallMonth = l.RecallMonth AND l2.EndUserName = l.EndUserName
                             AND ISNULL(l2.SaleName,'') = ISNULL(l.SaleName,'')
                           FOR XML PATH('')), 1, 2, '')
FROM dbo.v_Rc_RecallList l
GROUP BY RecallMonth, EndUserName, SaleName;
GO

/* =====================================================================
   PROC 3 : query สำหรับหน้าจอ Calibration Recall
   กรองด้วย Due Date (ไม่ใช่ Rec. Date) + คืน 2 result set: header, detail
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_RecallScreen
    @From       DATE,
    @To         DATE,
    @SaleName   NVARCHAR(100) = NULL,
    @Customer   NVARCHAR(255) = NULL,
    @CustomerID NVARCHAR(500) = NULL,      -- รหัสเดียว หรือหลายรหัสคั่นด้วย ,  (ขึ้นต้นตรงกันก็ได้)
    @StatusList VARCHAR(100)  = 'OPEN,NOTIFIED,QUOTED,ACCEPTED,SCHEDULED,OVERDUE'
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    INTO #d
    FROM dbo.v_Rc_RecallList
    WHERE DueDate BETWEEN @From AND @To
      AND (@SaleName IS NULL OR SaleName = @SaleName)
      AND (@Customer IS NULL OR EndUserName LIKE N'%' + @Customer + N'%')
      AND (@CustomerID IS NULL OR EXISTS (SELECT 1 FROM STRING_SPLIT(@CustomerID, ',') s
                                          WHERE CustomerID LIKE LTRIM(RTRIM(s.value)) + N'%'))
      AND ',' + @StatusList + ',' LIKE '%,' + RecallStatus + ',%';

    /* Header : ลูกค้า + QN เดิม  (ยอด = ราคารายการรวม ไม่ใช่ยอด QN ซ้ำต่อ RN) */
    SELECT CustomerID, EndUserName, SaleName, LastQNNo AS QNNo,
           RNList   = STUFF((SELECT DISTINCT ', ' + x.LastReceiveNo FROM #d x
                             WHERE x.EndUserName = d.EndUserName AND ISNULL(x.LastQNNo,'') = ISNULL(d.LastQNNo,'')
                             FOR XML PATH('')), 1, 2, ''),
           Qty      = COUNT(*),
           FirstDue = MIN(DueDate),
           EstCost  = SUM(ItemPrice),
           Overdue  = SUM(CASE WHEN RecallStatus = 'OVERDUE' THEN 1 ELSE 0 END)
    FROM #d d
    GROUP BY CustomerID, EndUserName, SaleName, LastQNNo
    ORDER BY MIN(DueDate), EndUserName;

    /* Detail */
    SELECT * FROM #d ORDER BY DueDate, EndUserName, CalID;

    /* Total Cost สำหรับกล่องด้านบน */
    SELECT TotalCost = SUM(ItemPrice), TotalItems = COUNT(*) FROM #d;
END;
GO

/* ---------------------------------------------------------------------
   v8: สถานะขั้นตอน Kanban (ACCEPTED / SCHEDULED) + ประวัติการเปลี่ยนสถานะ (ใช้ทำ Timeline)
   --------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('dbo.Rc_RecallTask')
           AND definition LIKE '%RecallStatus%' AND definition NOT LIKE '%SCHEDULED%')
BEGIN
    DECLARE @ck SYSNAME = (SELECT TOP 1 name FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('dbo.Rc_RecallTask') AND definition LIKE '%RecallStatus%');
    EXEC('ALTER TABLE dbo.Rc_RecallTask DROP CONSTRAINT ' + @ck);
    ALTER TABLE dbo.Rc_RecallTask ADD CONSTRAINT CK_Rc_RecallTask_Status
        CHECK (RecallStatus IN ('OPEN','NOTIFIED','QUOTED','ACCEPTED','SCHEDULED','RECEIVED','OVERDUE','CANCELLED'));
END;
GO
IF OBJECT_ID('dbo.Rc_RecallStatusHist') IS NULL
CREATE TABLE dbo.Rc_RecallStatusHist (
    HistID      INT IDENTITY(1,1) PRIMARY KEY,
    RecallID    INT NOT NULL REFERENCES dbo.Rc_RecallTask(RecallID),
    FromStatus  VARCHAR(12) NULL,
    ToStatus    VARCHAR(12) NOT NULL,
    ChangedBy   NVARCHAR(100) NULL,
    ChangedAt   DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Rc_RecallStatusHist_Recall')
    CREATE INDEX IX_Rc_RecallStatusHist_Recall ON dbo.Rc_RecallStatusHist(RecallID, ChangedAt);
GO

/* =====================================================================
   PROC 4 : บันทึกการแจ้งเตือน / ออก QN ใหม่ / ยกเลิก  (เรียกจากหน้าจอ)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_UpdateTask
    @RecallID  INT,
    @Action    VARCHAR(12),            -- NOTIFIED / QUOTED / ACCEPTED / SCHEDULED / CANCELLED / OPEN (ลากการ์ด Kanban)
    @NewQNNo   NVARCHAR(30)  = NULL,
    @Remark    NVARCHAR(500) = NULL,
    @ChangedBy NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Rc_RecallStatusHist(RecallID, FromStatus, ToStatus, ChangedBy)
    SELECT RecallID, RecallStatus, @Action, ISNULL(@ChangedBy, SUSER_SNAME())
      FROM dbo.Rc_RecallTask
     WHERE RecallID = @RecallID AND RecallStatus NOT IN ('RECEIVED') AND RecallStatus <> @Action;

    UPDATE dbo.Rc_RecallTask
       SET RecallStatus   = @Action,
           LastNotifyDate = CASE WHEN @Action = 'NOTIFIED' THEN CAST(GETDATE() AS DATE) ELSE LastNotifyDate END,
           NewQNNo        = ISNULL(@NewQNNo, NewQNNo),
           Remark         = ISNULL(@Remark, Remark),
           UpdatedAt      = SYSDATETIME()
     WHERE RecallID = @RecallID
       AND RecallStatus NOT IN ('RECEIVED');

    /* ยกเลิกเพราะเครื่องเลิกใช้ -> ไม่ต้อง recall รอบถัดไป */
    IF @Action = 'CANCELLED'
        UPDATE e SET IsActive = 0, InactiveReason = @Remark
        FROM dbo.Rc_Equipment e JOIN dbo.Rc_RecallTask t ON t.EquipmentID = e.EquipmentID
        WHERE t.RecallID = @RecallID;
END;
GO

/* =====================================================================
   ตัวอย่างการใช้งาน
   ---------------------------------------------------------------------
   EXEC dbo.sp_Rc_LoadFromStaging;
   EXEC dbo.sp_Rc_RunDaily @AsOf = '2026-11-19', @LeadDays = 90;

   -- หน้าจอเดิม: Sale = Ms. Mookkarin, Due 01/11/2026 - 19/11/2026
   EXEC dbo.sp_Rc_RecallScreen @From = '2026-11-01', @To = '2026-11-19',
        @SaleName = N'Ms. Mookkarin Dornkrajang';

   -- ค้นด้วย Customer ID
   EXEC dbo.sp_Rc_RecallScreen @From = '2026-11-01', @To = '2027-02-17', @CustomerID = N'CUS00330,CUS00412';

   -- รายการที่ต้องแจ้งลูกค้าภายใน 30 วัน
   SELECT * FROM dbo.v_Rc_RecallList WHERE DueBucket = N'ภายใน 30 วัน' ORDER BY DueDate;

   -- Cal ID ที่ไม่ใช่ PCAL ควรให้เจ้าหน้าที่ตรวจทาน
   SELECT * FROM dbo.Rc_Equipment WHERE IsWeakKey = 1;
   ===================================================================== */

/* =====================================================================
   ส่วนเพิ่ม : ออกใบเสนอราคาใหม่จากงาน Recall
   3 รูปแบบ  QN   = รวมเป็น 1 ใบต่อ QN เดิม
             RN   = แยกใบละ RN เดิม
             ITEM = แยกใบละเครื่อง
   ===================================================================== */
IF OBJECT_ID('dbo.Rc_NewQuotation') IS NULL
CREATE TABLE dbo.Rc_NewQuotation (
    NewQNNo      NVARCHAR(30) PRIMARY KEY,           -- เลขร่าง ระบบใบเสนอราคาจริงจะเปลี่ยนเป็นเลข QN จริง
    SplitMode    VARCHAR(4)   NOT NULL CHECK (SplitMode IN ('QN','RN','ITEM')),
    EndUserName  NVARCHAR(255) NOT NULL,
    SaleName     NVARCHAR(100) NULL,
    OldQNNo      NVARCHAR(30)  NULL,
    OldReceiveNo NVARCHAR(30)  NULL,                 -- มีค่าเมื่อแยกราย RN / รายเครื่อง
    ItemCount    INT           NOT NULL,
    EstAmount    DECIMAL(18,2) NOT NULL,
    QStatus      VARCHAR(10)   NOT NULL DEFAULT 'DRAFT' CHECK (QStatus IN ('DRAFT','SENT','ACCEPTED','CANCELLED')),
    CreatedBy    NVARCHAR(100) NULL,
    CreatedAt    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('dbo.Rc_NewQuotationItem') IS NULL
CREATE TABLE dbo.Rc_NewQuotationItem (
    NewQNNo   NVARCHAR(30) NOT NULL REFERENCES dbo.Rc_NewQuotation(NewQNNo),
    RecallID  INT          NOT NULL REFERENCES dbo.Rc_RecallTask(RecallID),
    ItemPrice DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_Rc_NewQuotationItem PRIMARY KEY (NewQNNo, RecallID)
);
GO

/* @RecallIDs = '101,102,103'  (เครื่องที่เลือก หรือทั้งกลุ่มที่ยังไม่มี QN ใหม่) */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_CreateQuotation
    @RecallIDs  NVARCHAR(MAX),
    @SplitMode  VARCHAR(4),               -- QN / RN / ITEM
    @CreatedBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @SplitMode NOT IN ('QN','RN','ITEM') THROW 50001, 'SplitMode ต้องเป็น QN / RN / ITEM', 1;

    DECLARE @yy CHAR(2) = RIGHT(CONVERT(CHAR(4), YEAR(GETDATE())), 2);

    BEGIN TRAN;

    /* รายการที่ออกได้: ยังไม่กลับมา/ไม่ยกเลิก และยังไม่อยู่ในใบร่างที่ไม่ถูกยกเลิก */
    SELECT l.RecallID, l.EndUserName, l.SaleName, l.LastQNNo, l.LastReceiveNo, l.ItemPrice,
           GroupKey = CASE @SplitMode WHEN 'QN'   THEN l.EndUserName + N'|' + ISNULL(l.LastQNNo, N'-')
                                      WHEN 'RN'   THEN l.EndUserName + N'|' + l.LastReceiveNo
                                      ELSE CONVERT(NVARCHAR(20), l.RecallID) END
    INTO #it
    FROM dbo.v_Rc_RecallList l
    JOIN STRING_SPLIT(@RecallIDs, ',') s ON TRY_CONVERT(INT, s.value) = l.RecallID
    WHERE l.RecallStatus NOT IN ('RECEIVED','CANCELLED')
      AND NOT EXISTS (SELECT 1 FROM dbo.Rc_NewQuotationItem qi
                      JOIN dbo.Rc_NewQuotation q ON q.NewQNNo = qi.NewQNNo AND q.QStatus <> 'CANCELLED'
                      WHERE qi.RecallID = l.RecallID);

    /* เลขร่างต่อเนื่อง QN-NEWnnnn/yy */
    DECLARE @last INT = ISNULL((SELECT MAX(TRY_CONVERT(INT, SUBSTRING(NewQNNo, 7, 4)))
                                FROM dbo.Rc_NewQuotation WITH (UPDLOCK, HOLDLOCK)
                                WHERE NewQNNo LIKE N'QN-NEW____/' + @yy), 0);

    SELECT GroupKey,
           NewQNNo = N'QN-NEW' + RIGHT('0000' + CONVERT(VARCHAR(10), @last + ROW_NUMBER() OVER (ORDER BY MIN(EndUserName), GroupKey)), 4) + N'/' + @yy,
           EndUserName = MIN(EndUserName), SaleName = MIN(SaleName),
           OldQNNo = CASE WHEN COUNT(DISTINCT LastQNNo) = 1 THEN MIN(LastQNNo) END,
           OldReceiveNo = CASE WHEN @SplitMode <> 'QN' OR COUNT(DISTINCT LastReceiveNo) = 1 THEN MIN(LastReceiveNo) END,
           ItemCount = COUNT(*), EstAmount = SUM(ItemPrice)
    INTO #q
    FROM #it GROUP BY GroupKey;

    INSERT dbo.Rc_NewQuotation (NewQNNo, SplitMode, EndUserName, SaleName, OldQNNo, OldReceiveNo, ItemCount, EstAmount, CreatedBy)
    SELECT NewQNNo, @SplitMode, EndUserName, SaleName, OldQNNo, OldReceiveNo, ItemCount, EstAmount, @CreatedBy FROM #q;

    INSERT dbo.Rc_NewQuotationItem (NewQNNo, RecallID, ItemPrice)
    SELECT q.NewQNNo, i.RecallID, i.ItemPrice FROM #it i JOIN #q q ON q.GroupKey = i.GroupKey;

    UPDATE t SET RecallStatus = 'QUOTED', NewQNNo = q.NewQNNo, UpdatedAt = SYSDATETIME()
    FROM dbo.Rc_RecallTask t JOIN #it i ON i.RecallID = t.RecallID JOIN #q q ON q.GroupKey = i.GroupKey;

    COMMIT;

    SELECT * FROM #q ORDER BY NewQNNo;        -- คืนรายการใบเสนอราคาที่สร้าง
END;
GO

/* ยกเลิกใบร่าง -> งาน recall กลับไปเป็น OPEN / OVERDUE */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_CancelQuotation @NewQNNo NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRAN;
    UPDATE dbo.Rc_NewQuotation SET QStatus = 'CANCELLED' WHERE NewQNNo = @NewQNNo;
    UPDATE t SET RecallStatus = CASE WHEN t.DueDate < CAST(GETDATE() AS DATE) THEN 'OVERDUE' ELSE 'OPEN' END,
                 NewQNNo = NULL, UpdatedAt = SYSDATETIME()
    FROM dbo.Rc_RecallTask t JOIN dbo.Rc_NewQuotationItem qi ON qi.RecallID = t.RecallID
    WHERE qi.NewQNNo = @NewQNNo AND t.RecallStatus = 'QUOTED';
    COMMIT;
END;
GO
/* ตัวอย่าง
   EXEC dbo.sp_Rc_CreateQuotation @RecallIDs = '101,102,103,104', @SplitMode = 'RN', @CreatedBy = N'Ms. Marasri';
   EXEC dbo.sp_Rc_CancelQuotation @NewQNNo = N'QN-NEW0002/26';
*/

/* #####################################################################
   ส่วนที่ 3 : บันทึกการติดตาม / แจ้งเตือนอัตโนมัติ / KPI
   ##################################################################### */

/* ---------------------------------------------------------------------
   3.1 ข้อมูลติดต่อ
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Rc_SaleContact') IS NULL
CREATE TABLE dbo.Rc_SaleContact (
    SaleName      NVARCHAR(100) PRIMARY KEY,      -- ต้องตรงกับ SaleName ใน Rc_CalEvent
    Email         NVARCHAR(200) NOT NULL,
    ManagerEmail  NVARCHAR(200) NULL,             -- cc สรุปเกินกำหนดให้หัวหน้า
    IsActive      BIT NOT NULL DEFAULT 1
);
GO
IF OBJECT_ID('dbo.Rc_CustomerContact') IS NULL
CREATE TABLE dbo.Rc_CustomerContact (
    ContactID       INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID      NVARCHAR(20)  NULL,
    EndUserName     NVARCHAR(255) NOT NULL,
    ContactName     NVARCHAR(150) NULL,
    Position        NVARCHAR(100) NULL,           -- ตำแหน่ง / แผนก
    Email           NVARCHAR(200) NULL,
    Phone           NVARCHAR(50)  NULL,
    IsRecallContact BIT NOT NULL DEFAULT 1,       -- 1 = ส่งอีเมลแจ้งเตือน recall ถึงคนนี้
    IsActive        BIT NOT NULL DEFAULT 1
);
GO

/* ---------------------------------------------------------------------
   3.2 เหตุผลที่ยกเลิก + บันทึกการติดตาม
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Rc_CancelReason') IS NULL
BEGIN
    CREATE TABLE dbo.Rc_CancelReason (
        ReasonCode   VARCHAR(20) PRIMARY KEY,
        ReasonText   NVARCHAR(100) NOT NULL,
        StopRecall   BIT NOT NULL DEFAULT 0        -- 1 = ไม่ต้อง recall เครื่องนี้อีก
    );
    INSERT dbo.Rc_CancelReason VALUES
      ('DISCONTINUED', N'เลิกใช้เครื่อง / เครื่องเสีย', 1),
      ('SOLD',         N'ขาย / โอนเครื่องไปที่อื่น',  1),
      ('COMPETITOR',   N'ย้ายไปใช้บริการเจ้าอื่น',     0),
      ('IN_HOUSE',     N'สอบเทียบเอง',               0),
      ('PRICE',        N'ราคาสูง',                    0),
      ('NOT_DUE',      N'ยังไม่ถึงรอบ / ขยายรอบ',     0),
      ('OTHER',        N'อื่น ๆ',                     0);
END;
GO
IF OBJECT_ID('dbo.Rc_ContactLog') IS NULL
BEGIN
    CREATE TABLE dbo.Rc_ContactLog (
        LogID            INT IDENTITY(1,1) PRIMARY KEY,
        RecallID         INT NOT NULL REFERENCES dbo.Rc_RecallTask(RecallID),
        ContactDate      DATE NOT NULL,
        ContactBy        NVARCHAR(100) NOT NULL,          -- Sale ผู้ติดต่อ
        ContactID        INT NULL REFERENCES dbo.Rc_CustomerContact(ContactID),  -- ผู้ติดต่อฝั่งลูกค้า (เลือกจากรายชื่อ)
        ContactPerson    NVARCHAR(150) NULL,              -- ชื่อ ณ วันที่บันทึก (เก็บไว้แม้รายชื่อถูกแก้ภายหลัง)
        Channel          VARCHAR(10) NOT NULL CHECK (Channel IN ('PHONE','EMAIL','LINE','VISIT','OTHER')),
        Result           VARCHAR(15) NOT NULL CHECK (Result IN ('INTERESTED','REQUEST_QUOTE','NOT_READY','NO_ANSWER','CANCEL')),
        CancelReasonCode VARCHAR(20) NULL REFERENCES dbo.Rc_CancelReason(ReasonCode),
        Competitor       NVARCHAR(150) NULL,              -- ถ้าย้ายไปเจ้าอื่น ระบุชื่อ
        NextFollowUp     DATE NULL,
        Note             NVARCHAR(1000) NULL,
        CreatedAt        DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
        CONSTRAINT CK_Rc_ContactLog_Cancel CHECK (Result <> 'CANCEL' OR CancelReasonCode IS NOT NULL)
    );
    CREATE INDEX IX_Rc_ContactLog_Recall ON dbo.Rc_ContactLog(RecallID, ContactDate DESC);
    CREATE INDEX IX_Rc_ContactLog_Follow ON dbo.Rc_ContactLog(NextFollowUp) WHERE NextFollowUp IS NOT NULL;
END;
GO

/* ถ้าสร้างตารางไปก่อนแล้ว ให้เพิ่มคอลัมน์ใหม่ */
IF COL_LENGTH('dbo.Rc_CustomerContact','Position') IS NULL ALTER TABLE dbo.Rc_CustomerContact ADD Position NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.Rc_ContactLog','ContactID') IS NULL ALTER TABLE dbo.Rc_ContactLog ADD ContactID INT NULL REFERENCES dbo.Rc_CustomerContact(ContactID);
GO

/* รายชื่อผู้ติดต่อของลูกค้า -> ใช้เติม dropdown "ผู้ติดต่อฝั่งลูกค้า" ใน modal บันทึกการติดตาม */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_GetCustomerContacts
    @CustomerID  NVARCHAR(20)  = NULL,
    @EndUserName NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ContactID, ContactName, Position, Phone, Email, IsRecallContact,
           LastContact = (SELECT MAX(l.ContactDate) FROM dbo.Rc_ContactLog l WHERE l.ContactID = c.ContactID)
    FROM dbo.Rc_CustomerContact c
    WHERE c.IsActive = 1
      AND ((@CustomerID IS NOT NULL AND c.CustomerID = @CustomerID)
        OR (@CustomerID IS NULL AND c.EndUserName = @EndUserName))
    ORDER BY c.IsRecallContact DESC, LastContact DESC, c.ContactName;
END;
GO

/* เพิ่มผู้ติดต่อใหม่จาก modal (ตัวเลือก "+ เพิ่มผู้ติดต่อใหม่") คืน ContactID */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_AddCustomerContact
    @CustomerID      NVARCHAR(20)  = NULL,
    @EndUserName     NVARCHAR(255),
    @ContactName     NVARCHAR(150),
    @Position        NVARCHAR(100) = NULL,
    @Phone           NVARCHAR(50)  = NULL,
    @Email           NVARCHAR(200) = NULL,
    @IsRecallContact BIT           = 1,
    @ContactID       INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ContactID = ContactID FROM dbo.Rc_CustomerContact
    WHERE IsActive = 1 AND ContactName = @ContactName
      AND (CustomerID = @CustomerID OR (@CustomerID IS NULL AND EndUserName = @EndUserName));
    IF @ContactID IS NULL
    BEGIN
        INSERT dbo.Rc_CustomerContact (CustomerID, EndUserName, ContactName, Position, Phone, Email, IsRecallContact)
        VALUES (@CustomerID, @EndUserName, @ContactName, @Position, @Phone, @Email, @IsRecallContact);
        SET @ContactID = SCOPE_IDENTITY();
    END;
    SELECT ContactID = @ContactID;
END;
GO

/* บันทึกการติดตาม (ทีละเครื่อง หรือหลายเครื่องพร้อมกัน) */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_AddContactLog
    @RecallIDs        NVARCHAR(MAX) = NULL,   -- ขอบเขตแบบเลือกรายเครื่อง
    @ScopeReceiveNo   NVARCHAR(30)  = NULL,   -- หรือ ทั้ง RN  (ทุกเครื่องที่ยังเปิดอยู่ใน RN นี้)
    @ScopeQNNo        NVARCHAR(30)  = NULL,   -- หรือ ทั้ง QN
    @ScopeEndUser     NVARCHAR(255) = NULL,   -- ใช้คู่กับ RN / QN เพื่อจำกัดเฉพาะลูกค้ารายนี้
    @ContactDate      DATE,
    @ContactBy        NVARCHAR(100),
    @ContactID        INT           = NULL,
    @ContactPerson    NVARCHAR(150) = NULL,
    @Channel          VARCHAR(10),
    @Result           VARCHAR(15),
    @CancelReasonCode VARCHAR(20)   = NULL,
    @Competitor       NVARCHAR(150) = NULL,
    @NextFollowUp     DATE          = NULL,
    @Note             NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Result = 'CANCEL' AND @CancelReasonCode IS NULL THROW 50002, N'ต้องระบุเหตุผลที่ยกเลิก', 1;

    CREATE TABLE #ids (RecallID INT PRIMARY KEY);
    IF @ScopeReceiveNo IS NOT NULL OR @ScopeQNNo IS NOT NULL
        INSERT #ids SELECT RecallID FROM dbo.v_Rc_RecallList
        WHERE RecallStatus NOT IN ('RECEIVED','CANCELLED')
          AND (@ScopeReceiveNo IS NULL OR LastReceiveNo = @ScopeReceiveNo)
          AND (@ScopeQNNo      IS NULL OR LastQNNo      = @ScopeQNNo)
          AND (@ScopeEndUser   IS NULL OR EndUserName   = @ScopeEndUser);
    ELSE
        INSERT #ids SELECT DISTINCT TRY_CONVERT(INT, value) FROM STRING_SPLIT(@RecallIDs, ',') WHERE TRY_CONVERT(INT, value) IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM #ids) THROW 50003, N'ไม่มีเครื่องในขอบเขตที่เลือก', 1;

    BEGIN TRAN;
    IF @ContactID IS NOT NULL AND @ContactPerson IS NULL
        SELECT @ContactPerson = ContactName + ISNULL(N' (' + Position + N')', N'') FROM dbo.Rc_CustomerContact WHERE ContactID = @ContactID;

    INSERT dbo.Rc_ContactLog (RecallID, ContactDate, ContactBy, ContactID, ContactPerson, Channel, Result, CancelReasonCode, Competitor, NextFollowUp, Note)
    SELECT RecallID, @ContactDate, @ContactBy, @ContactID, @ContactPerson, @Channel, @Result, @CancelReasonCode, @Competitor, @NextFollowUp, @Note FROM #ids;

    UPDATE t SET
        RecallStatus   = CASE WHEN @Result = 'CANCEL' THEN 'CANCELLED'
                              WHEN t.RecallStatus IN ('OPEN','OVERDUE') THEN 'NOTIFIED' ELSE t.RecallStatus END,
        LastNotifyDate = @ContactDate,
        Remark         = CASE WHEN @Result = 'CANCEL' THEN (SELECT ReasonText FROM dbo.Rc_CancelReason WHERE ReasonCode = @CancelReasonCode)
                                                       + ISNULL(N' : ' + @Competitor, N'') ELSE t.Remark END,
        UpdatedAt      = SYSDATETIME()
    FROM dbo.Rc_RecallTask t JOIN #ids i ON i.RecallID = t.RecallID
    WHERE t.RecallStatus NOT IN ('RECEIVED');

    /* เลิกใช้ / ขายไปแล้ว -> ไม่ต้อง recall รอบต่อไป */
    IF @Result = 'CANCEL' AND EXISTS (SELECT 1 FROM dbo.Rc_CancelReason WHERE ReasonCode = @CancelReasonCode AND StopRecall = 1)
        UPDATE e SET IsActive = 0, InactiveReason = @CancelReasonCode
        FROM dbo.Rc_Equipment e JOIN dbo.Rc_RecallTask t ON t.EquipmentID = e.EquipmentID JOIN #ids i ON i.RecallID = t.RecallID;
    COMMIT;
END;
GO

/* ---------------------------------------------------------------------
   3.3 แจ้งเตือนอัตโนมัติ (Database Mail)
   ต้องเปิด Database Mail และสร้าง Mail Profile ก่อน (เช่น 'RecallMail')
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.Rc_NotifyLog') IS NULL
BEGIN
    CREATE TABLE dbo.Rc_NotifyLog (
        NotifyID    INT IDENTITY(1,1) PRIMARY KEY,
        RecallID    INT NOT NULL REFERENCES dbo.Rc_RecallTask(RecallID),
        NotifyLevel SMALLINT NOT NULL,                 -- 90 / 60 / 30
        SentTo      VARCHAR(10) NOT NULL,              -- CUSTOMER / SALE
        Recipients  NVARCHAR(1000) NULL,
        MailItemID  INT NULL,
        SentAt      DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
        CONSTRAINT UQ_Rc_NotifyLog UNIQUE (RecallID, NotifyLevel, SentTo)
    );
END;
GO

/* ตาราง HTML รายการเครื่อง ใช้ร่วมกันทุกอีเมล */
CREATE OR ALTER FUNCTION dbo.fn_Rc_ItemTableHtml (@Items NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN N'<table border="1" cellpadding="5" cellspacing="0" style="border-collapse:collapse;font-family:Tahoma;font-size:12px">'
         + N'<tr style="background:#1f4e8c;color:#fff"><th>Due Date</th><th>Cal. ID</th><th>Description</th><th>Model</th><th>Manuf.</th><th>Serial No.</th><th>Last Cert.</th></tr>'
         + ISNULL(@Items, N'') + N'</table>';
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_Rc_SendNotifications
    @AsOf           DATE          = NULL,
    @MailProfile    SYSNAME       = N'RecallMail',
    @SendToCustomer BIT           = 0,        -- 0 = ส่งให้ Sale อย่างเดียว (แนะนำช่วงทดลอง), 1 = ส่งลูกค้าและ cc Sale
    @TestRecipient  NVARCHAR(200) = NULL      -- ใส่อีเมลตัวเองเพื่อทดสอบ อีเมลทุกฉบับจะส่งมาที่นี่ และไม่บันทึก log
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS DATE));

    /* งานที่ถึงรอบแจ้งเตือนและยังไม่เคยแจ้งรอบนั้น (ถ้าข้ามรอบ ส่งรอบล่าสุดรอบเดียว) */
    IF OBJECT_ID('tempdb..#due') IS NOT NULL DROP TABLE #due;
    SELECT l.RecallID, l.CustomerID, l.EndUserName, l.SaleName, l.DueDate, l.CalID, l.Description, l.Model, l.Manuf,
           l.SerialNo, l.LastCertNo,
           Lvl = CASE WHEN DATEDIFF(DAY, @AsOf, l.DueDate) <= 30 THEN 30
                      WHEN DATEDIFF(DAY, @AsOf, l.DueDate) <= 60 THEN 60 ELSE 90 END
    INTO #due
    FROM dbo.v_Rc_RecallList l
    WHERE l.RecallStatus IN ('OPEN','NOTIFIED')
      AND l.DueDate >= @AsOf
      AND DATEDIFF(DAY, @AsOf, l.DueDate) <= 90;

    DELETE d FROM #due d
    WHERE EXISTS (SELECT 1 FROM dbo.Rc_NotifyLog n WHERE n.RecallID = d.RecallID AND n.NotifyLevel <= d.Lvl);

    DECLARE @cust NVARCHAR(255), @cid NVARCHAR(20), @sale NVARCHAR(100), @lvl SMALLINT,
            @to NVARCHAR(1000), @cc NVARCHAR(1000), @subject NVARCHAR(300), @body NVARCHAR(MAX),
            @items NVARCHAR(MAX), @mailId INT, @sentTo VARCHAR(10);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT EndUserName, CustomerID, SaleName, Lvl FROM #due;
    OPEN c; FETCH NEXT FROM c INTO @cust, @cid, @sale, @lvl;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @items = CAST((
            SELECT td = CONVERT(CHAR(10), DueDate, 103), '', td = CalID, '', td = Description, '', td = ISNULL(Model,''), '',
                   td = ISNULL(Manuf,''), '', td = ISNULL(SerialNo,''), '', td = LastCertNo
            FROM #due WHERE EndUserName = @cust AND ISNULL(SaleName,'') = ISNULL(@sale,'') AND Lvl = @lvl
            ORDER BY DueDate, CalID
            FOR XML PATH('tr')) AS NVARCHAR(MAX));

        SET @cc = NULL;
        SELECT @cc = Email FROM dbo.Rc_SaleContact WHERE SaleName = @sale AND IsActive = 1;
        SET @to = NULL;
        IF @SendToCustomer = 1
            SELECT @to = STUFF((SELECT ';' + Email FROM dbo.Rc_CustomerContact
                                WHERE IsActive = 1 AND IsRecallContact = 1 AND Email IS NOT NULL
                                  AND (CustomerID = @cid OR (CustomerID IS NULL AND EndUserName = @cust))
                                FOR XML PATH('')), 1, 1, '');
        SET @sentTo = CASE WHEN @to IS NULL THEN 'SALE' ELSE 'CUSTOMER' END;
        IF @to IS NULL BEGIN SET @to = @cc; SET @cc = NULL; END;

        SET @subject = N'[Calibration Recall] เครื่องมือครบกำหนดสอบเทียบภายใน ' + CAST(@lvl AS NVARCHAR(3)) + N' วัน - ' + @cust;
        SET @body = N'<div style="font-family:Tahoma;font-size:13px">'
                  + N'<p>เรียน ' + @cust + N'</p>'
                  + N'<p>เครื่องมือต่อไปนี้จะครบกำหนดสอบเทียบภายใน <b>' + CAST(@lvl AS NVARCHAR(3)) + N' วัน</b> '
                  + N'เพื่อให้เครื่องมือของท่านมีผลสอบเทียบต่อเนื่อง กรุณาติดต่อกลับเพื่อนัดหมายหรือขอใบเสนอราคา</p>'
                  + dbo.fn_Rc_ItemTableHtml(@items)
                  + N'<p>Dear Customer, the instruments above are due for calibration within ' + CAST(@lvl AS NVARCHAR(3))
                  + N' days. Please contact us to schedule or request a quotation.</p>'
                  + N'<p>ติดต่อ: ' + ISNULL(@sale, N'') + N'</p></div>';

        IF @TestRecipient IS NOT NULL BEGIN SET @to = @TestRecipient; SET @cc = NULL; END;

        IF @to IS NOT NULL
        BEGIN
            EXEC msdb.dbo.sp_send_dbmail @profile_name = @MailProfile, @recipients = @to, @copy_recipients = @cc,
                 @subject = @subject, @body = @body, @body_format = 'HTML', @mailitem_id = @mailId OUTPUT;

            IF @TestRecipient IS NULL
                INSERT dbo.Rc_NotifyLog (RecallID, NotifyLevel, SentTo, Recipients, MailItemID)
                SELECT RecallID, @lvl, @sentTo, @to + ISNULL(';' + @cc, ''), @mailId
                FROM #due WHERE EndUserName = @cust AND ISNULL(SaleName,'') = ISNULL(@sale,'') AND Lvl = @lvl;

            IF @TestRecipient IS NULL
                UPDATE t SET NotifyLevel = @lvl, LastNotifyDate = @AsOf,
                             RecallStatus = CASE WHEN t.RecallStatus = 'OPEN' THEN 'NOTIFIED' ELSE t.RecallStatus END
                FROM dbo.Rc_RecallTask t JOIN #due d ON d.RecallID = t.RecallID
                WHERE d.EndUserName = @cust AND ISNULL(d.SaleName,'') = ISNULL(@sale,'') AND d.Lvl = @lvl;
        END;
        FETCH NEXT FROM c INTO @cust, @cid, @sale, @lvl;
    END;
    CLOSE c; DEALLOCATE c;
END;
GO

/* สรุปทุกเช้าให้ Sale: เกินกำหนด + ครบใน 7 วัน + นัดติดตามวันนี้ */
CREATE OR ALTER PROCEDURE dbo.sp_Rc_DailySaleSummary
    @AsOf          DATE          = NULL,
    @MailProfile   SYSNAME       = N'RecallMail',
    @TestRecipient NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS DATE));

    IF OBJECT_ID('tempdb..#s') IS NOT NULL DROP TABLE #s;
    SELECT l.SaleName, l.EndUserName, l.DueDate, l.CalID, l.Description, l.LastQNNo, l.ItemPrice, l.RecallStatus,
           DaysOver = DATEDIFF(DAY, l.DueDate, @AsOf),
           Grp = CASE WHEN l.DueDate < @AsOf THEN 1 ELSE 2 END,
           FollowUp = (SELECT MAX(c.NextFollowUp) FROM dbo.Rc_ContactLog c WHERE c.RecallID = l.RecallID)
    INTO #s
    FROM dbo.v_Rc_RecallList l
    WHERE l.RecallStatus IN ('OPEN','NOTIFIED','QUOTED','ACCEPTED','SCHEDULED','OVERDUE')
      AND l.DueDate <= DATEADD(DAY, 7, @AsOf);

    DECLARE @sale NVARCHAR(100), @to NVARCHAR(200), @mgr NVARCHAR(200), @body NVARCHAR(MAX), @subject NVARCHAR(300),
            @over NVARCHAR(MAX), @soon NVARCHAR(MAX), @nOver INT, @nSoon INT, @nFollow INT, @vOver DECIMAL(18,2);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.SaleName, sc.Email, sc.ManagerEmail
        FROM (SELECT DISTINCT SaleName FROM #s) s JOIN dbo.Rc_SaleContact sc ON sc.SaleName = s.SaleName AND sc.IsActive = 1;
    OPEN c; FETCH NEXT FROM c INTO @sale, @to, @mgr;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @over = NULL, @soon = NULL;
        SELECT @nOver = SUM(CASE WHEN Grp = 1 THEN 1 ELSE 0 END), @nSoon = SUM(CASE WHEN Grp = 2 THEN 1 ELSE 0 END),
               @nFollow = SUM(CASE WHEN FollowUp <= @AsOf THEN 1 ELSE 0 END),
               @vOver = SUM(CASE WHEN Grp = 1 THEN ItemPrice ELSE 0 END)
        FROM #s WHERE SaleName = @sale;

        /* เกินกำหนด: สรุปรายลูกค้า เรียงจากเกินนานสุด */
        SELECT @over = CAST((
            SELECT td = EndUserName, '', td = COUNT(*), '', td = MAX(DaysOver), '', td = FORMAT(SUM(ItemPrice), 'N2'), '',
                   td = ISNULL(CONVERT(CHAR(10), MAX(FollowUp), 103), '-')
            FROM #s WHERE SaleName = @sale AND Grp = 1
            GROUP BY EndUserName ORDER BY MAX(DaysOver) DESC
            FOR XML PATH('tr')) AS NVARCHAR(MAX));
        SELECT @soon = CAST((
            SELECT td = CONVERT(CHAR(10), DueDate, 103), '', td = EndUserName, '', td = CalID, '', td = Description
            FROM #s WHERE SaleName = @sale AND Grp = 2 ORDER BY DueDate
            FOR XML PATH('tr')) AS NVARCHAR(MAX));

        SET @subject = N'[Recall] สรุปประจำวัน ' + CONVERT(CHAR(10), @AsOf, 103) + N' : เกินกำหนด ' + CAST(ISNULL(@nOver,0) AS NVARCHAR(10))
                     + N' เครื่อง · ครบใน 7 วัน ' + CAST(ISNULL(@nSoon,0) AS NVARCHAR(10)) + N' เครื่อง';
        SET @body = N'<div style="font-family:Tahoma;font-size:13px"><p>สวัสดีครับ คุณ' + @sale + N'</p>'
                  + N'<ul><li>เกินกำหนดยังไม่กลับมา: <b>' + CAST(ISNULL(@nOver,0) AS NVARCHAR(10)) + N'</b> เครื่อง มูลค่าประมาณ <b>' + FORMAT(ISNULL(@vOver,0),'N2') + N'</b> บาท</li>'
                  + N'<li>ครบกำหนดใน 7 วัน: <b>' + CAST(ISNULL(@nSoon,0) AS NVARCHAR(10)) + N'</b> เครื่อง</li>'
                  + N'<li>นัดติดตามถึงวันนี้: <b>' + CAST(ISNULL(@nFollow,0) AS NVARCHAR(10)) + N'</b> เครื่อง</li></ul>'
                  + N'<h4>เกินกำหนด (รายลูกค้า)</h4><table border="1" cellpadding="5" cellspacing="0" style="border-collapse:collapse;font-size:12px">'
                  + N'<tr style="background:#c62828;color:#fff"><th>ลูกค้า</th><th>เครื่อง</th><th>เกินสูงสุด (วัน)</th><th>มูลค่า</th><th>นัดติดตาม</th></tr>'
                  + ISNULL(@over, N'') + N'</table>'
                  + N'<h4>ครบกำหนดใน 7 วัน</h4><table border="1" cellpadding="5" cellspacing="0" style="border-collapse:collapse;font-size:12px">'
                  + N'<tr style="background:#e65100;color:#fff"><th>Due Date</th><th>ลูกค้า</th><th>Cal. ID</th><th>Description</th></tr>'
                  + ISNULL(@soon, N'') + N'</table></div>';

        IF @TestRecipient IS NOT NULL SELECT @to = @TestRecipient, @mgr = NULL;
        EXEC msdb.dbo.sp_send_dbmail @profile_name = @MailProfile, @recipients = @to, @copy_recipients = @mgr,
             @subject = @subject, @body = @body, @body_format = 'HTML';

        FETCH NEXT FROM c INTO @sale, @to, @mgr;
    END;
    CLOSE c; DEALLOCATE c;
END;
GO

/* ---------------------------------------------------------------------
   3.4 SQL Agent Job : รันทุกวัน 07:30
   (แก้ @database_name ให้ตรงกับชื่อฐานข้อมูลจริง แล้วรันใน SSMS ครั้งเดียว)
   ---------------------------------------------------------------------
USE msdb;
EXEC dbo.sp_add_job        @job_name = N'Calibration Recall - Daily';
EXEC dbo.sp_add_jobstep    @job_name = N'Calibration Recall - Daily', @step_name = N'1 Update tasks',
     @subsystem = N'TSQL', @database_name = N'YourDB', @command = N'EXEC dbo.sp_Rc_RunDaily;', @on_success_action = 3;
EXEC dbo.sp_add_jobstep    @job_name = N'Calibration Recall - Daily', @step_name = N'2 Notify 90/60/30',
     @subsystem = N'TSQL', @database_name = N'YourDB', @command = N'EXEC dbo.sp_Rc_SendNotifications @SendToCustomer = 0;', @on_success_action = 3;
EXEC dbo.sp_add_jobstep    @job_name = N'Calibration Recall - Daily', @step_name = N'3 Sale summary',
     @subsystem = N'TSQL', @database_name = N'YourDB', @command = N'EXEC dbo.sp_Rc_DailySaleSummary;';
EXEC dbo.sp_add_schedule   @schedule_name = N'Daily 07:30', @freq_type = 4, @freq_interval = 1, @active_start_time = 073000;
EXEC dbo.sp_attach_schedule @job_name = N'Calibration Recall - Daily', @schedule_name = N'Daily 07:30';
EXEC dbo.sp_add_jobserver  @job_name = N'Calibration Recall - Daily';
   --------------------------------------------------------------------- */

/* ---------------------------------------------------------------------
   3.5 KPI สำหรับ Sales Manager
   Won  = เครื่องกลับมาสอบเทียบแล้ว (ยอดขาย = ราคารอบใหม่)
   Lost = ยกเลิก หรือเกินกำหนดมากกว่า @LostAfterDays (ค่าเริ่มต้น 90 วัน)
   Risk = เกินกำหนดแต่ยังไม่ถึงเกณฑ์ Lost (ยังตามได้)
   Pipe = ยังไม่ถึงกำหนด
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_Rc_KPI (@AsOf DATE, @LostAfterDays INT = 90)
RETURNS TABLE
AS RETURN
WITH x AS (
    SELECT src.SaleName, t.DueDate, DueMonth = CONVERT(CHAR(7), t.DueDate, 126),
           Outcome = CASE WHEN t.RecallStatus = 'RECEIVED' THEN 'WON'
                          WHEN t.RecallStatus = 'CANCELLED' THEN 'LOST'
                          WHEN t.DueDate < DATEADD(DAY, -@LostAfterDays, @AsOf) THEN 'LOST'
                          WHEN t.DueDate < @AsOf THEN 'RISK' ELSE 'PIPE' END,
           OldPrice = COALESCE(src.ItemPrice, src.ItemPriceEst, 0),
           NewPrice = COALESCE(ret.ItemPrice, ret.ItemPriceEst, 0)
    FROM dbo.Rc_RecallTask t
    JOIN dbo.Rc_CalEvent src ON src.CalEventID = t.SourceCalEventID
    LEFT JOIN dbo.Rc_CalEvent ret ON ret.CalEventID = t.ReturnCalEventID
)
SELECT SaleName, DueMonth,
       DueCount   = COUNT(*),
       WonCount   = SUM(CASE WHEN Outcome = 'WON'  THEN 1 ELSE 0 END),
       LostCount  = SUM(CASE WHEN Outcome = 'LOST' THEN 1 ELSE 0 END),
       RiskCount  = SUM(CASE WHEN Outcome = 'RISK' THEN 1 ELSE 0 END),
       PipeCount  = SUM(CASE WHEN Outcome = 'PIPE' THEN 1 ELSE 0 END),
       ReturnRatePct = CAST(100.0 * SUM(CASE WHEN Outcome = 'WON' THEN 1 ELSE 0 END)
                       / NULLIF(SUM(CASE WHEN Outcome <> 'PIPE' THEN 1 ELSE 0 END), 0) AS DECIMAL(5,1)),
       WonValue   = SUM(CASE WHEN Outcome = 'WON'  THEN NewPrice ELSE 0 END),
       LostValue  = SUM(CASE WHEN Outcome = 'LOST' THEN OldPrice ELSE 0 END),
       RiskValue  = SUM(CASE WHEN Outcome = 'RISK' THEN OldPrice ELSE 0 END),
       PipeValue  = SUM(CASE WHEN Outcome = 'PIPE' THEN OldPrice ELSE 0 END)
FROM x
GROUP BY SaleName, DueMonth;
GO

/* เหตุผลที่เสียลูกค้า แยกตาม Sale */
CREATE OR ALTER VIEW dbo.v_Rc_LostReason
AS
SELECT c.ContactBy AS SaleName, r.ReasonText, c.Competitor,
       Items = COUNT(*), LostValue = SUM(l.ItemPrice)
FROM dbo.Rc_ContactLog c
JOIN dbo.Rc_CancelReason r ON r.ReasonCode = c.CancelReasonCode
JOIN dbo.v_Rc_RecallList l ON l.RecallID = c.RecallID
WHERE c.Result = 'CANCEL'
GROUP BY c.ContactBy, r.ReasonText, c.Competitor;
GO

/* ตัวอย่าง
   EXEC dbo.sp_Rc_AddContactLog @RecallIDs='101,102', @ContactDate='2026-11-19', @ContactBy=N'Ms. Marasri Shukamnerd',
        @ContactID=12, @Channel='PHONE', @Result='CANCEL', @CancelReasonCode='COMPETITOR', @Competitor=N'บริษัท ABC';
   EXEC dbo.sp_Rc_AddContactLog @ScopeQNNo=N'QN13028/25', @ScopeEndUser=N'C.C.S. Advance Tech Co.,Ltd.', @ContactDate='2026-11-19',
        @ContactBy=N'Ms. Marasri Shukamnerd', @Channel='PHONE', @Result='INTERESTED', @NextFollowUp='2026-11-26';   -- บันทึกทั้ง QN
   EXEC dbo.sp_Rc_SendNotifications @TestRecipient = N'you@yourcompany.com';    -- ทดสอบส่งเข้าอีเมลตัวเอง
   EXEC dbo.sp_Rc_DailySaleSummary  @TestRecipient = N'you@yourcompany.com';
   SELECT * FROM dbo.fn_Rc_KPI('2026-11-19', 90) ORDER BY SaleName, DueMonth;
*/
