/* =====================================================================
   Customer Master v2 : รองรับลูกค้า 3 แบบ  USER / BROKER / FREELANCE
   SQL Server 2016 SP1+
   ---------------------------------------------------------------------
   แนวคิดหลัก
   1) ทุกคน (บริษัทลูกค้า, Broker, Freelance) อยู่ในตารางเดียว Cus_Party
      แยกด้วย PartyType  -> ใช้หน้าจอค้นหา/ที่อยู่/ผู้ติดต่อชุดเดียวกัน
   2) "ใครพามา" เก็บใน Cus_AgentLink (Broker/Freelance -> End User)
      ไม่เก็บชื่อ Broker ไว้ในช่อง Contact Name แบบของเดิมอีก
   2.1) บริษัทเดียวมีได้หลาย "แผนก / หน่วยงาน" (Cus_Unit) แต่ละแผนกมีผู้ติดต่อ,
        Sale, ที่อยู่รับ-ส่ง และ Customer Request ของตัวเอง
        Request สืบทอด: บริษัท (ค่ากลาง) -> แผนก (เพิ่ม/ยกเลิก) -> หมายเหตุรายเครื่อง
   2.2) สถานะลูกค้า PROSPECT -> ACTIVE -> DORMANT (18 ด.) -> LOST (24 ด.) คำนวณทุกคืน
        + ประวัติผู้ดูแล (Cus_SaleHist) และการโอนลูกค้าทีละหลายราย (ส่วนที่ 14)
   3) ทุกเอกสาร (RN / QN / Invoice / Cert) ระบุ 3 บทบาทแยกกัน (+ UnitID ของ End User)
         EndUserID  = เจ้าของเครื่อง ชื่อบน Cert, Recall ตามคนนี้
         BillToID   = ผู้สั่งซื้อ/ผู้จ่ายเงิน (End User หรือ Broker)
         AgentID    = Broker/Freelance ที่พามา (คิดค่าคอม / ส่วนลด)
   ---------------------------------------------------------------------
   นิยามที่ใช้ (ปรับได้)
     USER      : ลูกค้าปลายทาง เจ้าของเครื่อง จ่ายเงินเอง
     BROKER    : บริษัทตัวกลาง ซื้อบริการแล้วขายต่อ  -> Bill to Broker,
                 Cert เป็นชื่อ End User, ได้ราคา/ส่วนลด Broker
     FREELANCE : บุคคลธรรมดาที่แนะนำลูกค้า  -> Bill to End User,
                 Freelance ได้ค่าคอมมิชชัน (หัก ณ ที่จ่าย 3%)
   ===================================================================== */

/* ---------- 1. ประเภท ---------- */
IF OBJECT_ID('dbo.Cus_PartyType') IS NULL
BEGIN
CREATE TABLE dbo.Cus_PartyType (
    PartyType   VARCHAR(10) PRIMARY KEY,           -- USER / BROKER / FREELANCE
    NameTH      NVARCHAR(50) NOT NULL,
    IsAgent     BIT NOT NULL DEFAULT 0             -- 1 = พาลูกค้ามาได้
);
INSERT dbo.Cus_PartyType VALUES ('USER',N'ลูกค้าปลายทาง (End User)',0),('BROKER',N'Broker (บริษัทตัวกลาง)',1),('FREELANCE',N'Freelance (บุคคล)',1);
END;
GO

/* ---------- 2. กลุ่มบริษัท (แทนการใส่เลขนำหน้าชื่อ เช่น 1Charoen..., 2Charoen...) ---------- */
IF OBJECT_ID('dbo.Cus_Group') IS NULL
CREATE TABLE dbo.Cus_Group (
    GroupID     INT IDENTITY PRIMARY KEY,
    GroupName   NVARCHAR(200) NOT NULL UNIQUE      -- เช่น Charoen Pokphand Foods
);
GO

/* ---------- 3. Party (ลูกค้าทุกแบบ) : ต่อยอดจากตาราง Customer เดิม ---------- */
IF OBJECT_ID('dbo.Cus_Party') IS NULL
CREATE TABLE dbo.Cus_Party (
    PartyID         INT IDENTITY PRIMARY KEY,
    CustomerNo      VARCHAR(20)  NOT NULL UNIQUE,  -- C6490 (ของเดิม) / B0001 / F0001
    PartyType       VARCHAR(10)  NOT NULL REFERENCES dbo.Cus_PartyType(PartyType),
    LegalForm       CHAR(1)      NOT NULL DEFAULT 'C' CHECK (LegalForm IN ('C','P')), -- C=นิติบุคคล P=บุคคลธรรมดา
    AccountName     NVARCHAR(200) NOT NULL,        -- ชื่อออกบิล
    CertificateName NVARCHAR(200) NULL,            -- ชื่อบน Cert (USER)
    NameTH          NVARCHAR(200) NULL,
    TaxID           VARCHAR(13)  NULL,             -- นิติบุคคล 13 หลัก / เลขบัตรประชาชน (Freelance)
    BranchNo        VARCHAR(5)   NULL,             -- 00000 = สำนักงานใหญ่
    GroupID         INT NULL REFERENCES dbo.Cus_Group(GroupID),
    SaleID          INT NULL,                      -- FK ไปตารางพนักงานขายเดิม
    Phone           NVARCHAR(100) NULL,
    Fax             NVARCHAR(100) NULL,
    Email           NVARCHAR(200) NULL,
    Website         NVARCHAR(200) NULL,
    MapUrl          NVARCHAR(400) NULL,
    DiscountPct     DECIMAL(5,2) NOT NULL DEFAULT 0,
    CreditTerm      VARCHAR(10)  NULL,             -- CASH / CREDIT / POSTCHEQUE
    CreditDays      SMALLINT     NULL,
    IsActive        BIT NOT NULL DEFAULT 1,
    LegacyType      NVARCHAR(30) NULL,             -- ค่า Type เดิม (End Users / Broker / -)
    LegacyContact   NVARCHAR(300) NULL,            -- ค่า Contact Name เดิม (เก็บไว้ตรวจสอบตอนย้าย)
    CreatedAt       DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedAt       DATETIME2(0) NULL,
    CONSTRAINT CK_Cus_Party_Freelance CHECK (PartyType <> 'FREELANCE' OR LegalForm = 'P')
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Cus_Party_Type')
    CREATE INDEX IX_Cus_Party_Type ON dbo.Cus_Party(PartyType, IsActive) INCLUDE (AccountName, CustomerNo);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='UX_Cus_Party_Tax')
    CREATE UNIQUE INDEX UX_Cus_Party_Tax ON dbo.Cus_Party(TaxID, BranchNo) WHERE TaxID IS NOT NULL;   -- กันลูกค้าซ้ำ
GO

/* ---------- 4. ที่อยู่ (Account / Certificate / Office / Delivery) แยกแถว ---------- */
IF OBJECT_ID('dbo.Cus_Address') IS NULL
CREATE TABLE dbo.Cus_Address (
    AddressID   INT IDENTITY PRIMARY KEY,
    PartyID     INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    AddrType    VARCHAR(10) NOT NULL CHECK (AddrType IN ('BILL','CERT','OFFICE','DELIVERY')),
    AddressText NVARCHAR(500) NOT NULL,
    Province    NVARCHAR(100) NULL,
    PostCode    VARCHAR(5) NULL,
    IsDefault   BIT NOT NULL DEFAULT 1
);
GO

/* ---------- 4.1 แผนก / หน่วยงาน ภายในบริษัท ---------- */
IF OBJECT_ID('dbo.Cus_Unit') IS NULL
CREATE TABLE dbo.Cus_Unit (
    UnitID          INT IDENTITY PRIMARY KEY,
    PartyID         INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    UnitCode        VARCHAR(10)  NOT NULL,          -- 01, 02, QA, PD ...
    UnitName        NVARCHAR(150) NOT NULL,         -- QA, Production, Maintenance, Plant 2 ...
    SaleID          INT NULL,                       -- NULL = ใช้ Sale ของบริษัท
    CertName        NVARCHAR(200) NULL,             -- NULL = ใช้ชื่อบน Cert ของบริษัท
    CertAddress     NVARCHAR(500) NULL,
    PickupAddress   NVARCHAR(500) NULL,             -- ที่รับ-ส่งเครื่องของแผนก
    Phone           NVARCHAR(100) NULL,
    Email           NVARCHAR(200) NULL,             -- อีเมลกลางของแผนก
    IsDefault       BIT NOT NULL DEFAULT 0,         -- แผนกเริ่มต้นตอนเปิด RN
    IsActive        BIT NOT NULL DEFAULT 1,
    Remark          NVARCHAR(300) NULL,
    CONSTRAINT UQ_Cus_Unit UNIQUE (PartyID, UnitCode)
);
GO

/* ---------- 5. ผู้ติดต่อ (แท็บ Contact Items) : 1 คน = 1 แถว ---------- */
IF OBJECT_ID('dbo.Cus_Contact') IS NULL
CREATE TABLE dbo.Cus_Contact (
    ContactID   INT IDENTITY PRIMARY KEY,
    PartyID     INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    UnitID      INT NULL REFERENCES dbo.Cus_Unit(UnitID),   -- NULL = ผู้ติดต่อระดับบริษัท (เช่น บัญชี/จัดซื้อ)
    ContactName NVARCHAR(150) NOT NULL,
    Position    NVARCHAR(100) NULL,
    Phone       NVARCHAR(100) NULL,
    Mobile      NVARCHAR(50)  NULL,
    Fax         NVARCHAR(50)  NULL,
    Email       NVARCHAR(200) NULL,
    IsDefault   BIT NOT NULL DEFAULT 0,
    IsRecall    BIT NOT NULL DEFAULT 0,            -- รับอีเมลแจ้ง Recall
    IsActive    BIT NOT NULL DEFAULT 1
);
GO

/* ---------- 6. ข้อมูลเฉพาะ Broker / Freelance ---------- */
IF OBJECT_ID('dbo.Cus_AgentProfile') IS NULL
CREATE TABLE dbo.Cus_AgentProfile (
    PartyID         INT PRIMARY KEY REFERENCES dbo.Cus_Party(PartyID),
    PriceTier       VARCHAR(10) NULL,              -- ราคา Broker (เช่น B1, B2)
    BrokerDiscPct   DECIMAL(5,2) NULL,             -- ส่วนลดที่ Broker ได้
    CommissionPct   DECIMAL(5,2) NULL,             -- ค่าคอม Freelance
    WHTPct          DECIMAL(5,2) NULL,             -- หัก ณ ที่จ่าย (Freelance 3%)
    BankName        NVARCHAR(100) NULL,
    BankAccountNo   VARCHAR(30)  NULL,
    BankAccountName NVARCHAR(150) NULL,
    IDCardFile      NVARCHAR(400) NULL,            -- สำเนาบัตร / ภพ.20
    ContractStart   DATE NULL,
    ContractEnd     DATE NULL,
    DefaultNotify   VARCHAR(10) NOT NULL DEFAULT 'AGENT' CHECK (DefaultNotify IN ('AGENT','ENDUSER','BOTH'))
);
GO

/* ---------- 7. ความสัมพันธ์ Agent -> End User (หัวใจของการออกแบบ) ---------- */
IF OBJECT_ID('dbo.Cus_AgentLink') IS NULL
CREATE TABLE dbo.Cus_AgentLink (
    LinkID          INT IDENTITY PRIMARY KEY,
    AgentID         INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),   -- BROKER / FREELANCE
    EndUserID       INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),   -- USER
    UnitID          INT NULL REFERENCES dbo.Cus_Unit(UnitID),         -- NULL = ทั้งบริษัท / ระบุ = เฉพาะแผนก
    StartDate       DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    EndDate         DATE NULL,                     -- NULL = ยังดูแลอยู่
    IsExclusive     BIT NOT NULL DEFAULT 1,        -- ห้าม Sale เราติดต่อลูกค้าตรง
    CommissionPct   DECIMAL(5,2) NULL,             -- ทับค่าใน AgentProfile ได้
    NotifyVia       VARCHAR(10) NULL CHECK (NotifyVia IN ('AGENT','ENDUSER','BOTH')),  -- ใครได้อีเมล Recall
    Remark          NVARCHAR(300) NULL,
    CONSTRAINT CK_Cus_AgentLink_Self CHECK (AgentID <> EndUserID)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='UX_Cus_AgentLink_Active')
    CREATE UNIQUE INDEX UX_Cus_AgentLink_Active ON dbo.Cus_AgentLink(EndUserID, UnitID, AgentID) WHERE EndDate IS NULL;
GO

/* ตรวจชนิดก่อนผูก (CHECK ข้ามตารางทำไม่ได้ จึงใช้ trigger) */
CREATE OR ALTER TRIGGER dbo.trg_Cus_AgentLink_Check ON dbo.Cus_AgentLink AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted i JOIN dbo.Cus_Party a ON a.PartyID=i.AgentID WHERE a.PartyType NOT IN ('BROKER','FREELANCE'))
       OR EXISTS (SELECT 1 FROM inserted i JOIN dbo.Cus_Party u ON u.PartyID=i.EndUserID WHERE u.PartyType <> 'USER')
    BEGIN
        RAISERROR(N'AgentID ต้องเป็น BROKER/FREELANCE และ EndUserID ต้องเป็น USER',16,1); ROLLBACK; RETURN;
    END
END;
GO

/* ---------- 8. Customer Request (แท็บเดิม) : เก็บเป็นแถว ไม่ต้องเพิ่มคอลัมน์ทุกครั้งที่มีข้อใหม่ ---------- */
IF OBJECT_ID('dbo.Cus_RequestItem') IS NULL
CREATE TABLE dbo.Cus_RequestItem (       -- master ของ checkbox
    ReqCode     VARCHAR(30) PRIMARY KEY,           -- CERT_DESC, DATA_TOL, STK_DUE, ONSITE_SAFETY ...
    Section     VARCHAR(20) NOT NULL,              -- CERTIFICATE / DATA / ONSITE / STICKER / SPECIAL / PACKAGE / QUALITY
    LabelTH     NVARCHAR(100) NOT NULL,
    SortNo      SMALLINT NOT NULL DEFAULT 0
);
IF OBJECT_ID('dbo.Cus_Request') IS NULL
CREATE TABLE dbo.Cus_Request (
    ReqID       INT IDENTITY PRIMARY KEY,
    PartyID     INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    UnitID      INT NULL REFERENCES dbo.Cus_Unit(UnitID),       -- NULL = ค่ากลางของบริษัท / Broker
    ReqCode     VARCHAR(30) NOT NULL REFERENCES dbo.Cus_RequestItem(ReqCode),
    Mode        CHAR(1) NOT NULL DEFAULT 'Y' CHECK (Mode IN ('Y','N')),  -- Y = ต้องการ, N = แผนกนี้ยกเลิกข้อของบริษัท
    Note        NVARCHAR(500) NULL
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='UX_Cus_Request')
    CREATE UNIQUE INDEX UX_Cus_Request ON dbo.Cus_Request(PartyID, UnitID, ReqCode);
/* หมายเหตุรายเครื่อง (ชั้นที่ 3) เก็บที่ทะเบียนเครื่อง เช่น Rc_Equipment.SpecialRequest */
GO

/* ---------- 9. เพิ่ม 3 บทบาทในเอกสารเดิม (ตัวอย่าง: ใส่ชื่อตารางจริงของ RN/QN) ----------
ALTER TABLE dbo.ReceiveHeader   ADD EndUserID INT NULL, UnitID INT NULL, BillToID INT NULL, AgentID INT NULL;
ALTER TABLE dbo.QuotationHeader ADD EndUserID INT NULL, UnitID INT NULL, BillToID INT NULL, AgentID INT NULL;
ALTER TABLE dbo.Rc_Equipment    ADD UnitID INT NULL;   -- เครื่องอยู่แผนกไหน -> Recall ส่งถึงผู้ติดต่อของแผนกนั้น
-- ค่าเริ่มต้นตอนเปิด RN/QN: เลือก End User -> ระบบหา Agent ที่ active ใน Cus_AgentLink
--   ถ้า Agent เป็น BROKER    : BillTo = Broker
--   ถ้า Agent เป็น FREELANCE : BillTo = End User, บันทึกค่าคอมให้ Freelance
------------------------------------------------------------------------------------------- */

/* ---------- 10. ค่าคอม Freelance ---------- */
IF OBJECT_ID('dbo.Cus_Commission') IS NULL
CREATE TABLE dbo.Cus_Commission (
    CommID      INT IDENTITY PRIMARY KEY,
    AgentID     INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    EndUserID   INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    DocNo       NVARCHAR(30) NOT NULL,             -- Invoice / QN
    DocDate     DATE NOT NULL,
    BaseAmount  DECIMAL(14,2) NOT NULL,
    CommPct     DECIMAL(5,2) NOT NULL,
    CommAmount  AS CAST(BaseAmount*CommPct/100 AS DECIMAL(14,2)) PERSISTED,
    WHTAmount   DECIMAL(14,2) NULL,
    Status      VARCHAR(10) NOT NULL DEFAULT 'PENDING' CHECK (Status IN ('PENDING','APPROVED','PAID','CANCELLED')),
    PaidDate    DATE NULL
);
GO

/* ---------- 11. View ที่หน้าจอ / Recall ใช้ ---------- */
CREATE OR ALTER VIEW dbo.v_Cus_EndUserAgent AS
SELECT  u.PartyID AS EndUserID, u.CustomerNo, u.AccountName AS EndUserName,
        a.PartyID AS AgentID, a.CustomerNo AS AgentNo, a.AccountName AS AgentName, a.PartyType AS AgentType,
        BillToID   = CASE WHEN a.PartyType='BROKER' THEN a.PartyID ELSE u.PartyID END,
        NotifyVia  = COALESCE(l.NotifyVia, p.DefaultNotify, 'ENDUSER'),
        CommPct    = COALESCE(l.CommissionPct, p.CommissionPct),
        l.IsExclusive
FROM dbo.Cus_Party u
LEFT JOIN dbo.Cus_AgentLink   l ON l.EndUserID=u.PartyID AND l.EndDate IS NULL
LEFT JOIN dbo.Cus_Party       a ON a.PartyID=l.AgentID
LEFT JOIN dbo.Cus_AgentProfile p ON p.PartyID=a.PartyID
WHERE u.PartyType='USER';
GO
/* Recall: ส่งอีเมลหาใคร  -> ใช้ NotifyVia
     AGENT   : ส่งให้ Broker/Freelance (กันการข้ามหัว Broker)
     ENDUSER : ส่งให้ผู้ติดต่อ IsRecall=1 ของ End User
     BOTH    : ส่งทั้งคู่  */

/* ---------- 11.1 Customer Request ที่ใช้จริงของแต่ละแผนก (สืบทอดจากบริษัท) ---------- */
CREATE OR ALTER VIEW dbo.v_Cus_UnitRequest AS
WITH u AS (
    SELECT un.UnitID, un.PartyID FROM dbo.Cus_Unit un WHERE un.IsActive = 1
), allReq AS (                              -- ข้อของบริษัท + ข้อของแผนก
    SELECT u.UnitID, u.PartyID, r.ReqCode, r.Mode, r.Note, Lvl = 1
    FROM u JOIN dbo.Cus_Request r ON r.PartyID = u.PartyID AND r.UnitID IS NULL
    UNION ALL
    SELECT u.UnitID, u.PartyID, r.ReqCode, r.Mode, r.Note, Lvl = 2
    FROM u JOIN dbo.Cus_Request r ON r.UnitID = u.UnitID
), pick AS (
    SELECT *, rn = ROW_NUMBER() OVER (PARTITION BY UnitID, ReqCode ORDER BY Lvl DESC) FROM allReq
)
SELECT p.UnitID, p.PartyID, p.ReqCode, i.Section, i.LabelTH, p.Note,
       Source = CASE p.Lvl WHEN 2 THEN N'แผนก' ELSE N'บริษัท' END
FROM pick p JOIN dbo.Cus_RequestItem i ON i.ReqCode = p.ReqCode
WHERE p.rn = 1 AND p.Mode = 'Y';
GO
/* ใช้ตอนรับเครื่อง:  SELECT * FROM dbo.v_Cus_UnitRequest WHERE UnitID = @UnitID ORDER BY Section */

/* ---------- 11.2 ผู้รับอีเมล Recall รายแผนก ---------- */
CREATE OR ALTER VIEW dbo.v_Cus_UnitRecallContact AS
SELECT un.UnitID, un.PartyID, c.ContactID, c.ContactName, c.Email
FROM dbo.Cus_Unit un
JOIN dbo.Cus_Contact c ON c.PartyID = un.PartyID AND c.IsActive = 1 AND c.IsRecall = 1
     AND (c.UnitID = un.UnitID
          OR (c.UnitID IS NULL AND NOT EXISTS (SELECT 1 FROM dbo.Cus_Contact x
                 WHERE x.UnitID = un.UnitID AND x.IsActive = 1 AND x.IsRecall = 1)))  -- แผนกไม่มีคนรับ -> ใช้ของบริษัท
WHERE un.IsActive = 1 AND c.Email IS NOT NULL;
GO

/* =====================================================================
   12. ย้ายข้อมูลจากของเดิม (Customer.XLSX / ตาราง Customer เดิม)
   ขั้นที่ 1  โหลด Excel เข้า dbo.Stg_Customer (Import Wizard) คอลัมน์:
              CustomerNo, CustomerName, Address, Type, Phone, Fax, Email, Website, ContactName, Position
   ===================================================================== */
/*
-- 12.1 ล้างค่า "-" ให้เป็น NULL
UPDATE dbo.Stg_Customer SET
  Phone       = NULLIF(NULLIF(LTRIM(RTRIM(Phone)),'-'),''),
  Fax         = NULLIF(NULLIF(LTRIM(RTRIM(Fax)),'-'),''),
  Email       = NULLIF(NULLIF(LTRIM(RTRIM(Email)),'-'),''),
  Website     = NULLIF(NULLIF(LTRIM(RTRIM(Website)),'-'),''),
  ContactName = NULLIF(NULLIF(LTRIM(RTRIM(ContactName)),'-'),''),
  Position    = NULLIF(NULLIF(LTRIM(RTRIM(Position)),'-'),'');

-- 12.2 Party : ทุกแถวเดิมเป็น USER ไว้ก่อน (แม้ Type = Broker) เพราะแถว "Broker" เดิม
--      ส่วนใหญ่คือบริษัทลูกค้าที่ Broker พามา (ชื่อ Broker ไปอยู่ในช่อง Contact)
INSERT dbo.Cus_Party (CustomerNo, PartyType, AccountName, CertificateName, Phone, Fax, Email, Website, LegacyType, LegacyContact)
SELECT CustomerNo, 'USER', LTRIM(RTRIM(REPLACE(REPLACE(CustomerName,'   ',' '),'  ',' '))), CustomerName,
       Phone, Fax, Email, Website, Type, ContactName
FROM dbo.Stg_Customer;

INSERT dbo.Cus_Address (PartyID, AddrType, AddressText)
SELECT p.PartyID, 'BILL', s.Address FROM dbo.Stg_Customer s JOIN dbo.Cus_Party p ON p.CustomerNo=s.CustomerNo
WHERE NULLIF(NULLIF(LTRIM(RTRIM(s.Address)),'-'),'') IS NOT NULL;

-- 12.3 ผู้ติดต่อ : แถวที่ Type เดิม = End Users ย้ายตรง
--      (ช่องที่มีหลายคน/มีเบอร์ปน เช่น "คุณ A / 089-xxx" ให้แยกด้วยมือหรือ script แยก "/" ภายหลัง)
INSERT dbo.Cus_Contact (PartyID, ContactName, Position, IsDefault, IsRecall)
SELECT p.PartyID, s.ContactName, s.Position, 1, 1
FROM dbo.Stg_Customer s JOIN dbo.Cus_Party p ON p.CustomerNo=s.CustomerNo
WHERE s.ContactName IS NOT NULL AND ISNULL(s.Type,'') <> 'Broker';

-- 12.4 Broker : สร้างจากชื่อในช่อง Contact ของแถว Type=Broker (ไมโครเทค, ES, Entech, HI-TECH, ...)
--      ทำตาราง map ด้วยมือก่อน (67 ชื่อ) : dbo.Stg_BrokerMap(LegacyContact, AgentNo, AgentName, AgentType)
--      AgentType = BROKER ถ้าเป็นบริษัท, FREELANCE ถ้าเป็นบุคคล (เช่น "พี่หมู", "ลูกค้าพี่บอส ...")
INSERT dbo.Cus_Party (CustomerNo, PartyType, LegalForm, AccountName)
SELECT DISTINCT AgentNo, AgentType, CASE WHEN AgentType='FREELANCE' THEN 'P' ELSE 'C' END, AgentName
FROM dbo.Stg_BrokerMap m WHERE NOT EXISTS (SELECT 1 FROM dbo.Cus_Party p WHERE p.CustomerNo=m.AgentNo);

INSERT dbo.Cus_AgentProfile (PartyID, DefaultNotify)
SELECT PartyID, 'AGENT' FROM dbo.Cus_Party p
WHERE PartyType IN ('BROKER','FREELANCE') AND NOT EXISTS (SELECT 1 FROM dbo.Cus_AgentProfile x WHERE x.PartyID=p.PartyID);

INSERT dbo.Cus_AgentLink (AgentID, EndUserID, StartDate)
SELECT a.PartyID, u.PartyID, '2000-01-01'
FROM dbo.Cus_Party u
JOIN dbo.Stg_BrokerMap m ON m.LegacyContact = u.LegacyContact
JOIN dbo.Cus_Party a ON a.CustomerNo = m.AgentNo
WHERE u.LegacyType = 'Broker';

-- 12.5 แถวที่เป็นบริษัท Broker เอง (เช่น A.S. Metrology, ACL (2550)) : เปลี่ยนชนิด
-- UPDATE dbo.Cus_Party SET PartyType='BROKER' WHERE CustomerNo IN ('C....','C....');

-- 12.6 กลุ่มบริษัท : ชื่อที่ขึ้นต้นด้วยเลข (1Charoen..., 2Charoen...) -> ตัดเลขออก ผูก GroupID + ใส่ BranchNo
--      ถ้าเป็นนิติบุคคล + สาขาเดียวกันแต่แยกแถวเพราะคนละแผนก -> รวมเป็น Party เดียว แล้วสร้าง Cus_Unit ต่อแถวเดิม

-- 12.7 ทุกบริษัทต้องมีอย่างน้อย 1 แผนก (แผนกหลัก) เพื่อให้ RN / Recall อ้างอิงได้
INSERT dbo.Cus_Unit (PartyID, UnitCode, UnitName, IsDefault)
SELECT p.PartyID, '01', N'หลัก', 1 FROM dbo.Cus_Party p
WHERE p.PartyType = 'USER' AND NOT EXISTS (SELECT 1 FROM dbo.Cus_Unit u WHERE u.PartyID = p.PartyID);
UPDATE c SET UnitID = u.UnitID FROM dbo.Cus_Contact c JOIN dbo.Cus_Unit u ON u.PartyID = c.PartyID AND u.IsDefault = 1 WHERE c.UnitID IS NULL;
*/

/* ---------- 13. ตรวจหลังย้าย ---------- */
/*
SELECT PartyType, COUNT(*) FROM dbo.Cus_Party GROUP BY PartyType;
SELECT * FROM dbo.Cus_Party WHERE LegacyType='Broker' AND PartyType='USER'
  AND NOT EXISTS (SELECT 1 FROM dbo.Cus_AgentLink l WHERE l.EndUserID=PartyID);   -- Broker เดิมที่ยังไม่ได้ผูก
SELECT TaxID, BranchNo, COUNT(*) FROM dbo.Cus_Party WHERE TaxID IS NOT NULL GROUP BY TaxID, BranchNo HAVING COUNT(*)>1;
*/

/* =====================================================================
   14. วงจรสถานะลูกค้า (Lifecycle) + โอนลูกค้าเมื่อ Sale เปลี่ยน
   ===================================================================== */
IF COL_LENGTH('dbo.Cus_Party','CustomerStatus') IS NULL
    ALTER TABLE dbo.Cus_Party ADD
        CustomerStatus   VARCHAR(10) NOT NULL CONSTRAINT DF_Cus_Party_Status DEFAULT 'PROSPECT'
            CONSTRAINT CK_Cus_Party_Status CHECK (CustomerStatus IN ('PROSPECT','ACTIVE','DORMANT','LOST','CLOSED')),
        StatusReasonCode VARCHAR(20)  NULL,     -- ใช้รหัสเดียวกับ Rc_CancelReason (COMPETITOR, PRICE, ...) หรือ NOJOB
        StatusCompetitor NVARCHAR(150) NULL,
        StatusManual     BIT NOT NULL CONSTRAINT DF_Cus_Party_StMan DEFAULT 0,  -- 1 = Sale ตั้งเอง (LOST/PROSPECT) ไม่ให้ job ทับ
        StatusDate       DATE NULL,
        LastJobDate      DATE NULL;           -- วันที่รับเครื่อง/สอบเทียบล่าสุด (job เติมให้)
GO

/* เกณฑ์ (ปรับได้) */
IF OBJECT_ID('dbo.Cus_Setting') IS NULL
BEGIN
    CREATE TABLE dbo.Cus_Setting (SettingKey VARCHAR(30) PRIMARY KEY, SettingValue INT NOT NULL, Remark NVARCHAR(200) NULL);
    INSERT dbo.Cus_Setting VALUES ('DORMANT_MONTHS',18,N'ไม่มีงานกี่เดือนถือว่าห่างหาย'),('LOST_MONTHS',24,N'ไม่มีงานกี่เดือนถือว่าเสียลูกค้า');
END;
GO

/* ประวัติสถานะ */
IF OBJECT_ID('dbo.Cus_StatusHist') IS NULL
CREATE TABLE dbo.Cus_StatusHist (
    HistID      INT IDENTITY PRIMARY KEY,
    PartyID     INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    FromStatus  VARCHAR(10) NULL,
    ToStatus    VARCHAR(10) NOT NULL,
    ReasonCode  VARCHAR(20) NULL,
    Competitor  NVARCHAR(150) NULL,
    Note        NVARCHAR(300) NULL,
    ChangedBy   NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),   -- 'SYSTEM' เมื่อ job เปลี่ยน
    ChangedAt   DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);
GO

/* ประวัติผู้ดูแล (Sale) : 1 แถว = 1 ช่วงเวลา, ValidTo NULL = ปัจจุบัน */
IF OBJECT_ID('dbo.Cus_SaleHist') IS NULL
CREATE TABLE dbo.Cus_SaleHist (
    SaleHistID  INT IDENTITY PRIMARY KEY,
    PartyID     INT NOT NULL REFERENCES dbo.Cus_Party(PartyID),
    UnitID      INT NULL REFERENCES dbo.Cus_Unit(UnitID),      -- NULL = ระดับบริษัท
    SaleID      INT NULL,
    ValidFrom   DATE NOT NULL,
    ValidTo     DATE NULL,
    TransferID  INT NULL,                                       -- มาจากการโอนชุดไหน
    Note        NVARCHAR(300) NULL
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Cus_SaleHist')
    CREATE INDEX IX_Cus_SaleHist ON dbo.Cus_SaleHist(PartyID, UnitID, ValidFrom);
GO

/* หัวเอกสารการโอน (ไว้ดูย้อนหลัง / ย้อนกลับ) */
IF OBJECT_ID('dbo.Cus_SaleTransfer') IS NULL
CREATE TABLE dbo.Cus_SaleTransfer (
    TransferID     INT IDENTITY PRIMARY KEY,
    FromSaleID     INT NULL,
    ToSaleID       INT NOT NULL,
    EffectiveDate  DATE NOT NULL,
    ReasonCode     VARCHAR(10) NOT NULL CHECK (ReasonCode IN ('RESIGN','TERRITORY','REORG','REQUEST','OTHER')),
    Note           NVARCHAR(300) NULL,
    IncludeUnits   BIT NOT NULL DEFAULT 1,
    MoveRecall     BIT NOT NULL DEFAULT 1,
    PartyCount     INT NOT NULL DEFAULT 0,
    CreatedBy      NVARCHAR(100) NOT NULL DEFAULT SUSER_SNAME(),
    CreatedAt      DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    UndoneAt       DATETIME2(0) NULL
);
GO

/* ---------- 14.1 คำนวณสถานะอัตโนมัติ (SQL Agent ทุกคืน) ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_Cus_RefreshStatus
    @AsOf DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS DATE));
    DECLARE @dm INT = (SELECT SettingValue FROM dbo.Cus_Setting WHERE SettingKey='DORMANT_MONTHS'),
            @lm INT = (SELECT SettingValue FROM dbo.Cus_Setting WHERE SettingKey='LOST_MONTHS');

    /* 1) วันที่มีงานล่าสุด จากประวัติสอบเทียบ (ปรับเป็นตาราง RN จริงได้) */
    ;WITH lj AS (
        SELECT p.PartyID, MAX(ce.CalDate) AS LastJob
        FROM dbo.Cus_Party p
        JOIN dbo.Rc_Equipment eq ON eq.CustomerID = p.CustomerNo
        JOIN dbo.Rc_CalEvent  ce ON ce.EquipmentID = eq.EquipmentID
        GROUP BY p.PartyID)
    UPDATE p SET LastJobDate = lj.LastJob
    FROM dbo.Cus_Party p JOIN lj ON lj.PartyID = p.PartyID
    WHERE ISNULL(p.LastJobDate,'19000101') <> lj.LastJob;

    /* 2) สถานะใหม่ */
    DECLARE @chg TABLE (PartyID INT, FromS VARCHAR(10), ToS VARCHAR(10), Reason VARCHAR(20), Comp NVARCHAR(150));
    ;WITH calc AS (
        SELECT p.PartyID, p.CustomerStatus AS OldS, p.StatusManual, p.StatusDate, p.LastJobDate,
               NewS = CASE
                   WHEN p.IsActive = 0 THEN 'CLOSED'
                   WHEN p.PartyType <> 'USER' THEN 'ACTIVE'
                   /* Sale ตั้งเสียลูกค้าเอง: คงไว้ จนกว่าจะมีงานใหม่หลังวันที่ตั้ง (= ได้ลูกค้ากลับมา) */
                   WHEN p.StatusManual = 1 AND p.CustomerStatus = 'LOST' AND (p.LastJobDate IS NULL OR p.LastJobDate <= p.StatusDate) THEN 'LOST'
                   WHEN p.LastJobDate IS NULL THEN 'PROSPECT'
                   WHEN DATEDIFF(MONTH, p.LastJobDate, @AsOf) <  @dm THEN 'ACTIVE'
                   WHEN DATEDIFF(MONTH, p.LastJobDate, @AsOf) <  @lm THEN 'DORMANT'
                   ELSE 'LOST' END
        FROM dbo.Cus_Party p)
    UPDATE p SET
        CustomerStatus   = c.NewS,
        StatusManual     = CASE WHEN c.NewS = 'LOST' AND p.StatusManual = 1 THEN 1 ELSE 0 END,
        StatusReasonCode = CASE WHEN c.NewS = 'LOST' AND p.StatusManual = 1 THEN p.StatusReasonCode
                                WHEN c.NewS = 'LOST' THEN ISNULL(r.TopReason, 'NOJOB') ELSE NULL END,
        StatusCompetitor = CASE WHEN c.NewS = 'LOST' AND p.StatusManual = 1 THEN p.StatusCompetitor
                                WHEN c.NewS = 'LOST' THEN r.TopComp ELSE NULL END,
        StatusDate       = @AsOf
    OUTPUT inserted.PartyID, deleted.CustomerStatus, inserted.CustomerStatus, inserted.StatusReasonCode, inserted.StatusCompetitor INTO @chg
    FROM dbo.Cus_Party p
    JOIN calc c ON c.PartyID = p.PartyID
    /* เหตุผลที่เสีย: ใช้เหตุผล "ยกเลิก" ที่พบบ่อยสุดจากบันทึกการติดตามในระบบ Recall */
    OUTER APPLY (SELECT TOP 1 cl.CancelReasonCode AS TopReason, MAX(cl.Competitor) AS TopComp
                 FROM dbo.Rc_ContactLog cl
                 JOIN dbo.Rc_RecallTask t ON t.RecallID = cl.RecallID
                 JOIN dbo.Rc_Equipment eq ON eq.EquipmentID = t.EquipmentID
                 WHERE eq.CustomerID = p.CustomerNo AND cl.Result = 'CANCEL'
                 GROUP BY cl.CancelReasonCode ORDER BY COUNT(*) DESC) r
    WHERE c.NewS <> c.OldS;

    INSERT dbo.Cus_StatusHist (PartyID, FromStatus, ToStatus, ReasonCode, Competitor, Note, ChangedBy)
    SELECT PartyID, FromS, ToS, Reason, Comp,
           CASE WHEN ToS='ACTIVE' AND FromS IN ('DORMANT','LOST') THEN N'ลูกค้ากลับมามีงาน' ELSE N'คำนวณอัตโนมัติ' END, 'SYSTEM'
    FROM @chg;
END;
GO

/* ---------- 14.2 Sale ตั้งสถานะเอง (เสียลูกค้า / ลูกค้าเป้าหมาย / ยกเลิก) ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_Cus_SetStatus
    @PartyID INT, @Status VARCHAR(10), @ReasonCode VARCHAR(20) = NULL, @Competitor NVARCHAR(150) = NULL, @Note NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Status = 'LOST' AND @ReasonCode IS NULL BEGIN RAISERROR(N'ตั้งเสียลูกค้าต้องระบุเหตุผล',16,1); RETURN; END;
    DECLARE @old VARCHAR(10) = (SELECT CustomerStatus FROM dbo.Cus_Party WHERE PartyID=@PartyID);
    UPDATE dbo.Cus_Party SET CustomerStatus=@Status, StatusManual=CASE WHEN @Status IN ('LOST','PROSPECT') THEN 1 ELSE 0 END,
           StatusReasonCode=@ReasonCode, StatusCompetitor=@Competitor, StatusDate=CAST(GETDATE() AS DATE), UpdatedAt=SYSDATETIME()
    WHERE PartyID=@PartyID;
    INSERT dbo.Cus_StatusHist (PartyID, FromStatus, ToStatus, ReasonCode, Competitor, Note) VALUES (@PartyID, @old, @Status, @ReasonCode, @Competitor, @Note);
    IF @Status <> 'LOST' EXEC dbo.sp_Cus_RefreshStatus;   -- ยกเลิก LOST -> ให้ระบบคำนวณใหม่
END;
GO

/* ---------- 14.3 โอนลูกค้าทีละหลายราย ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_Cus_TransferSale
    @FromSaleID   INT,                       -- NULL = ลูกค้าที่ยังไม่มี Sale
    @ToSaleID     INT,
    @PartyIDs     NVARCHAR(MAX),             -- '12,15,99'  (ว่าง = ลูกค้าทั้งหมดของ @FromSaleID)
    @EffectiveDate DATE = NULL,
    @ReasonCode   VARCHAR(10) = 'OTHER',
    @Note         NVARCHAR(300) = NULL,
    @IncludeUnits BIT = 1,
    @MoveRecall   BIT = 1
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @EffectiveDate = ISNULL(@EffectiveDate, CAST(GETDATE() AS DATE));
    DECLARE @ids TABLE (PartyID INT PRIMARY KEY);
    INSERT @ids SELECT p.PartyID FROM dbo.Cus_Party p
    WHERE ((@FromSaleID IS NULL AND p.SaleID IS NULL) OR p.SaleID = @FromSaleID)
      AND (NULLIF(@PartyIDs,'') IS NULL OR p.PartyID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@PartyIDs, ',')));

    BEGIN TRAN;
    INSERT dbo.Cus_SaleTransfer (FromSaleID, ToSaleID, EffectiveDate, ReasonCode, Note, IncludeUnits, MoveRecall, PartyCount)
    VALUES (@FromSaleID, @ToSaleID, @EffectiveDate, @ReasonCode, @Note, @IncludeUnits, @MoveRecall, (SELECT COUNT(*) FROM @ids));
    DECLARE @tid INT = SCOPE_IDENTITY();

    /* ปิดช่วงเดิม + เปิดช่วงใหม่ (ระดับบริษัท) */
    UPDATE h SET ValidTo = DATEADD(DAY,-1,@EffectiveDate)
    FROM dbo.Cus_SaleHist h JOIN @ids i ON i.PartyID = h.PartyID WHERE h.UnitID IS NULL AND h.ValidTo IS NULL;
    INSERT dbo.Cus_SaleHist (PartyID, UnitID, SaleID, ValidFrom, TransferID, Note)
    SELECT PartyID, NULL, @ToSaleID, @EffectiveDate, @tid, @Note FROM @ids;
    UPDATE p SET SaleID = @ToSaleID, UpdatedAt = SYSDATETIME() FROM dbo.Cus_Party p JOIN @ids i ON i.PartyID = p.PartyID;

    /* แผนกที่ตั้ง Sale เป็นคนเดิม */
    IF @IncludeUnits = 1
    BEGIN
        UPDATE h SET ValidTo = DATEADD(DAY,-1,@EffectiveDate)
        FROM dbo.Cus_SaleHist h JOIN dbo.Cus_Unit u ON u.UnitID = h.UnitID JOIN @ids i ON i.PartyID = u.PartyID
        WHERE h.ValidTo IS NULL AND u.SaleID = @FromSaleID;
        INSERT dbo.Cus_SaleHist (PartyID, UnitID, SaleID, ValidFrom, TransferID, Note)
        SELECT u.PartyID, u.UnitID, @ToSaleID, @EffectiveDate, @tid, @Note
        FROM dbo.Cus_Unit u JOIN @ids i ON i.PartyID = u.PartyID WHERE u.SaleID = @FromSaleID;
        UPDATE u SET SaleID = @ToSaleID FROM dbo.Cus_Unit u JOIN @ids i ON i.PartyID = u.PartyID WHERE u.SaleID = @FromSaleID;
    END;

    /* งาน Recall ที่ยังเปิดอยู่ย้ายตาม (ตาราง Rc_Equipment.SaleName เป็นชื่อ: map ผ่านตารางพนักงาน) */
    IF @MoveRecall = 1
        UPDATE eq SET SaleName = (SELECT SaleName FROM dbo.Sale WHERE SaleID = @ToSaleID)   -- ปรับชื่อตารางพนักงานจริง
        FROM dbo.Rc_Equipment eq
        JOIN dbo.Cus_Party p ON p.CustomerNo = eq.CustomerID
        JOIN @ids i ON i.PartyID = p.PartyID
        WHERE EXISTS (SELECT 1 FROM dbo.Rc_RecallTask t WHERE t.EquipmentID = eq.EquipmentID
                      AND t.RecallStatus IN ('OPEN','NOTIFIED','QUOTED','ACCEPTED','SCHEDULED','OVERDUE'));
    COMMIT;
    SELECT @tid AS TransferID, (SELECT COUNT(*) FROM @ids) AS PartyCount;
END;
GO

/* ย้อนกลับการโอน (เฉพาะรายที่ยังเป็น Sale ปลายทาง) */
CREATE OR ALTER PROCEDURE dbo.sp_Cus_UndoTransfer @TransferID INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @from INT, @to INT, @eff DATE;
    SELECT @from=FromSaleID, @to=ToSaleID, @eff=EffectiveDate FROM dbo.Cus_SaleTransfer WHERE TransferID=@TransferID AND UndoneAt IS NULL;
    IF @to IS NULL BEGIN RAISERROR(N'ไม่พบการโอน หรือย้อนกลับไปแล้ว',16,1); RETURN; END;
    BEGIN TRAN;
    UPDATE p SET SaleID=@from FROM dbo.Cus_Party p JOIN dbo.Cus_SaleHist h ON h.PartyID=p.PartyID AND h.UnitID IS NULL
      WHERE h.TransferID=@TransferID AND h.ValidTo IS NULL AND p.SaleID=@to;
    UPDATE u SET SaleID=@from FROM dbo.Cus_Unit u JOIN dbo.Cus_SaleHist h ON h.UnitID=u.UnitID
      WHERE h.TransferID=@TransferID AND h.ValidTo IS NULL AND u.SaleID=@to;
    DELETE FROM dbo.Cus_SaleHist WHERE TransferID=@TransferID AND ValidTo IS NULL;
    UPDATE h SET ValidTo=NULL FROM dbo.Cus_SaleHist h                       -- เปิดช่วงเดิมกลับ
      WHERE h.ValidTo = DATEADD(DAY,-1,@eff) AND NOT EXISTS (SELECT 1 FROM dbo.Cus_SaleHist x WHERE x.PartyID=h.PartyID AND ISNULL(x.UnitID,0)=ISNULL(h.UnitID,0) AND x.ValidTo IS NULL);
    UPDATE dbo.Cus_SaleTransfer SET UndoneAt=SYSDATETIME() WHERE TransferID=@TransferID;
    COMMIT;
END;
GO

/* ---------- 14.4 ใครดูแล ณ วันที่ (ใช้คิดยอดขาย / KPI / ค่าคอม ให้ถูกคน) ---------- */
CREATE OR ALTER FUNCTION dbo.fn_Cus_SaleAt (@PartyID INT, @UnitID INT, @AtDate DATE)
RETURNS TABLE AS RETURN
SELECT TOP 1 h.SaleID
FROM dbo.Cus_SaleHist h
WHERE h.PartyID = @PartyID AND (h.UnitID = @UnitID OR h.UnitID IS NULL)
  AND h.ValidFrom <= @AtDate AND (h.ValidTo IS NULL OR h.ValidTo >= @AtDate)
ORDER BY CASE WHEN h.UnitID IS NULL THEN 1 ELSE 0 END;     -- แผนกก่อน แล้วค่อยบริษัท
GO
/* ตัวอย่าง: ยอดขายเดือนก่อนการโอนยังนับให้ Sale เดิม
   SELECT inv.InvoiceNo, s.SaleID FROM dbo.Invoice inv CROSS APPLY dbo.fn_Cus_SaleAt(inv.EndUserID, inv.UnitID, inv.InvoiceDate) s; */

/* SQL Agent: ทุกวัน 01:00  ->  EXEC dbo.sp_Cus_RefreshStatus; */

/* ---------- 14.5 ย้ายข้อมูลเดิม ---------- */
/*
EXEC dbo.sp_Cus_RefreshStatus;   -- เติม LastJobDate + สถานะครั้งแรก
INSERT dbo.Cus_SaleHist (PartyID, UnitID, SaleID, ValidFrom, Note)
SELECT PartyID, NULL, SaleID, '2000-01-01', N'ข้อมูลเดิม' FROM dbo.Cus_Party WHERE SaleID IS NOT NULL;
*/
