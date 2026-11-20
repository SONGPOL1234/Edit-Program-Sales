/* =====================================================================
   PCal - Training Management (ทีมอบรมมาตรวิทยา)
   SQL Server 2016+ · ต่อกับ Customer Master (CustomerId) และข้อมูลสอบเทียบ (หาลูกค้าเป้าหมาย)
   ตาราง:  Tr_Course, Tr_Trainer, Tr_Class, Tr_Registration, Tr_Attendee, Tr_LeadFollow, Tr_Setting
   วิว:    v_Tr_ClassSummary, v_Tr_CertStatus, v_Tr_Leads, v_Tr_RevenueMonthly
   Proc:   sp_Tr_OpenClass, sp_Tr_Register, sp_Tr_IssueCertificates, sp_Tr_TargetProgress
   ===================================================================== */
SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.Tr_Setting') IS NULL
BEGIN
  CREATE TABLE dbo.Tr_Setting(
    SettingKey   VARCHAR(50)  NOT NULL PRIMARY KEY,
    SettingValue NVARCHAR(200) NOT NULL);
  INSERT dbo.Tr_Setting VALUES ('TargetGrowthPct','10'),('PassScore','60'),('LeadMinInstruments','20'),
                               ('CertExpireWarnDays','90'),('CertExpiredLookbackDays','180');
END
GO

/* ---------- 1. Master ---------- */
IF OBJECT_ID('dbo.Tr_Course') IS NULL
CREATE TABLE dbo.Tr_Course(
  CourseId      INT IDENTITY PRIMARY KEY,
  CourseCode    VARCHAR(20)   NOT NULL UNIQUE,          -- TR-101
  CourseName    NVARCHAR(250) NOT NULL,
  InstCategory  TINYINT       NOT NULL DEFAULT 5,       -- 0 มิติ 1 ความดัน 2 อุณหภูมิ 3 มวล 4 ไฟฟ้า 5 ทั่วไป/ระบบคุณภาพ
  Hours         DECIMAL(5,1)  NOT NULL,
  PublicPrice   DECIMAL(12,2) NOT NULL,                 -- ต่อคน
  InhousePrice  DECIMAL(12,2) NOT NULL,                 -- ต่อรอบ
  DefaultSeats  SMALLINT      NOT NULL DEFAULT 25,
  CertValidYears TINYINT      NOT NULL DEFAULT 3,
  NextCourseId  INT           NULL REFERENCES dbo.Tr_Course(CourseId),  -- หลักสูตรต่อยอด
  PrereqCourseId INT          NULL REFERENCES dbo.Tr_Course(CourseId),
  Active        BIT           NOT NULL DEFAULT 1
);
GO
IF OBJECT_ID('dbo.Tr_Trainer') IS NULL
CREATE TABLE dbo.Tr_Trainer(
  TrainerId     INT IDENTITY PRIMARY KEY,
  TrainerName   NVARCHAR(150) NOT NULL,
  Expertise     NVARCHAR(200) NULL,
  IsExternal    BIT           NOT NULL DEFAULT 0,
  FeePerDay     DECIMAL(12,2) NULL,
  Active        BIT           NOT NULL DEFAULT 1
);
GO

/* ---------- 2. Class (รอบอบรม) ---------- */
IF OBJECT_ID('dbo.Tr_Class') IS NULL
CREATE TABLE dbo.Tr_Class(
  ClassNo       VARCHAR(20)   NOT NULL PRIMARY KEY,     -- TRyy-###
  CourseId      INT           NOT NULL REFERENCES dbo.Tr_Course(CourseId),
  ClassType     CHAR(1)       NOT NULL CHECK (ClassType IN ('P','I')),  -- Public / In-house
  StartDate     DATE          NOT NULL,
  Days          TINYINT       NOT NULL DEFAULT 1,
  Venue         NVARCHAR(200) NULL,
  TrainerId     INT           NULL REFERENCES dbo.Tr_Trainer(TrainerId),
  Seats         SMALLINT      NOT NULL,
  Price         DECIMAL(12,2) NOT NULL,                 -- P = ต่อคน, I = ต่อรอบ
  CustomerId    VARCHAR(20)   NULL,                     -- In-house เท่านั้น
  Status        VARCHAR(10)   NOT NULL DEFAULT 'OPEN' CHECK (Status IN ('OPEN','DONE','CANCEL')),
  CancelReason  NVARCHAR(200) NULL,
  CreatedBy     NVARCHAR(50)  NULL,
  CreatedAt     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
  EndDate AS (DATEADD(DAY, Days-1, StartDate)) PERSISTED,
  CONSTRAINT CK_Tr_Class_Inhouse CHECK (ClassType='P' OR CustomerId IS NOT NULL)
);
CREATE INDEX IX_Tr_Class_Date ON dbo.Tr_Class(StartDate);
GO

/* ---------- 3. Registration / Attendee ---------- */
IF OBJECT_ID('dbo.Tr_Registration') IS NULL
CREATE TABLE dbo.Tr_Registration(
  RegId         INT IDENTITY PRIMARY KEY,
  ClassNo       VARCHAR(20)   NOT NULL REFERENCES dbo.Tr_Class(ClassNo),
  CustomerId    VARCHAR(20)   NOT NULL,
  RegDate       DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE),
  Source        VARCHAR(5)    NOT NULL DEFAULT 'TEAM' CHECK (Source IN ('SALE','TEAM','WEB')), -- SALE = Sale สอบเทียบส่งต่อ
  ReferSaleName NVARCHAR(100) NULL,                     -- Sale ที่ได้เครดิตขายข้ามธุรกิจ
  QuotationNo   VARCHAR(20)   NULL,                     -- ใบเสนอราคา Subject = Training
  PONo          VARCHAR(50)   NULL,
  InvoiceNo     VARCHAR(30)   NULL,
  Amount        DECIMAL(12,2) NOT NULL,
  PayStatus     VARCHAR(5)    NOT NULL DEFAULT '' CHECK (PayStatus IN ('','INV','PAID')),
  ContactName   NVARCHAR(100) NULL,
  ContactEmail  VARCHAR(150)  NULL
);
CREATE INDEX IX_Tr_Reg_Cust ON dbo.Tr_Registration(CustomerId);
GO
IF OBJECT_ID('dbo.Tr_Attendee') IS NULL
CREATE TABLE dbo.Tr_Attendee(
  AttendeeId    INT IDENTITY PRIMARY KEY,
  RegId         INT           NOT NULL REFERENCES dbo.Tr_Registration(RegId) ON DELETE CASCADE,
  FullName      NVARCHAR(150) NOT NULL,
  Position      NVARCHAR(100) NULL,
  Email         VARCHAR(150)  NULL,
  Phone         VARCHAR(30)   NULL,
  Attended      BIT           NULL,                     -- NULL = ยังไม่อบรม
  Score         DECIMAL(5,1)  NULL,
  CertNo        VARCHAR(20)   NULL UNIQUE,              -- PCTyy-#####
  CertIssueDate DATE          NULL,
  CertExpireDate DATE         NULL
);
CREATE INDEX IX_Tr_Att_Exp ON dbo.Tr_Attendee(CertExpireDate) WHERE CertNo IS NOT NULL;
GO

IF OBJECT_ID('dbo.Tr_LeadFollow') IS NULL
CREATE TABLE dbo.Tr_LeadFollow(
  LeadType      CHAR(1)       NOT NULL CHECK (LeadType IN ('A','B','C')),
  CustomerId    VARCHAR(20)   NOT NULL,
  CourseId      INT           NOT NULL,
  FollowStatus  CHAR(1)       NOT NULL CHECK (FollowStatus IN ('C','Q','W','X')), -- ติดต่อ/เสนอราคา/ได้สมัคร/ไม่สนใจ
  Note          NVARCHAR(300) NULL,
  UpdatedBy     NVARCHAR(50)  NULL,
  UpdatedAt     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
  PRIMARY KEY (LeadType, CustomerId, CourseId)
);
GO

/* ---------- 4. Views ---------- */
CREATE OR ALTER VIEW dbo.v_Tr_ClassSummary AS
SELECT c.ClassNo,c.StartDate,c.EndDate,c.ClassType,c.Status,co.CourseCode,co.CourseName,c.Venue,t.TrainerName,c.Seats,c.CustomerId,
       ISNULL(r.Pax,0) Pax, CAST(CASE WHEN c.Seats>0 THEN ISNULL(r.Pax,0)*100.0/c.Seats END AS DECIMAL(5,1)) FillPct,
       CASE WHEN c.Status='CANCEL' THEN 0 ELSE ISNULL(r.Amt,0) END Revenue,
       ISNULL(a.Attended,0) Attended, ISNULL(a.Passed,0) Passed, a.AvgScore,
       CASE WHEN c.Status='OPEN' AND c.ClassType='P' AND ISNULL(r.Pax,0)<c.Seats*0.5
                 AND DATEDIFF(DAY,CAST(GETDATE() AS DATE),c.StartDate) BETWEEN 0 AND 21 THEN 1 ELSE 0 END LowFillWarning
FROM dbo.Tr_Class c
JOIN dbo.Tr_Course co ON co.CourseId=c.CourseId
LEFT JOIN dbo.Tr_Trainer t ON t.TrainerId=c.TrainerId
OUTER APPLY (SELECT COUNT(*) Pax, (SELECT SUM(Amount) FROM dbo.Tr_Registration WHERE ClassNo=c.ClassNo) Amt
             FROM dbo.Tr_Attendee x JOIN dbo.Tr_Registration g ON g.RegId=x.RegId WHERE g.ClassNo=c.ClassNo) r
OUTER APPLY (SELECT SUM(CASE WHEN x.Attended=1 THEN 1 ELSE 0 END) Attended, SUM(CASE WHEN x.CertNo IS NOT NULL THEN 1 ELSE 0 END) Passed,
                    CAST(AVG(x.Score) AS DECIMAL(5,1)) AvgScore
             FROM dbo.Tr_Attendee x JOIN dbo.Tr_Registration g ON g.RegId=x.RegId WHERE g.ClassNo=c.ClassNo) a;
GO

CREATE OR ALTER VIEW dbo.v_Tr_CertStatus AS
SELECT x.AttendeeId,x.FullName,x.Position,g.CustomerId,c.ClassNo,co.CourseId,co.CourseCode,co.CourseName,c.StartDate,
       x.Attended,x.Score,x.CertNo,x.CertExpireDate,
       CASE WHEN x.CertNo IS NULL THEN CASE WHEN x.Attended=0 THEN 'ABSENT' WHEN x.Score IS NOT NULL THEN 'FAIL' ELSE 'PENDING' END
            WHEN x.CertExpireDate < CAST(GETDATE() AS DATE) THEN 'EXPIRED'
            WHEN x.CertExpireDate <= DATEADD(DAY,90,CAST(GETDATE() AS DATE)) THEN 'SOON'
            ELSE 'VALID' END CertStatus
FROM dbo.Tr_Attendee x
JOIN dbo.Tr_Registration g ON g.RegId=x.RegId
JOIN dbo.Tr_Class c ON c.ClassNo=g.ClassNo AND c.Status<>'CANCEL'
JOIN dbo.Tr_Course co ON co.CourseId=c.CourseId;
GO

/* ลูกค้าเป้าหมาย
   A: ส่งเครื่องสอบเทียบ >= 20 เครื่อง/24 เดือน แต่ไม่เคยส่งคนอบรม -> หลักสูตรตามประเภทเครื่องที่ส่งมากที่สุด
   B: ใบประกาศหมดอายุภายใน 90 วัน หรือหมดแล้วไม่เกิน 180 วัน -> หลักสูตรเดิม (ทบทวน)
   C: เรียนหลักสูตรที่มี NextCourseId แล้ว แต่ยังไม่เรียนหลักสูตรต่อยอด
   หมายเหตุ: dbo.v_Cal_InstrumentByCustomer(CustomerId, InstCategory, Qty24m) ต้องสร้างจากตารางเครื่องมือสอบเทียบจริง */
CREATE OR ALTER VIEW dbo.v_Tr_Leads AS
WITH inst AS (
  SELECT CustomerId, SUM(Qty24m) Total,
         (SELECT TOP 1 i2.InstCategory FROM dbo.v_Cal_InstrumentByCustomer i2 WHERE i2.CustomerId=i.CustomerId ORDER BY i2.Qty24m DESC) TopCat
  FROM dbo.v_Cal_InstrumentByCustomer i GROUP BY CustomerId),
trained AS (SELECT DISTINCT CustomerId FROM dbo.Tr_Registration),
A AS (
  SELECT 'A' LeadType, i.CustomerId,
         (SELECT TOP 1 CourseId FROM dbo.Tr_Course WHERE InstCategory=i.TopCat AND Active=1 ORDER BY CourseCode) CourseId,
         CONCAT(N'ส่งสอบเทียบ ',i.Total,N' เครื่อง/24 ด.') Reason, i.Total Score
  FROM inst i WHERE i.Total >= (SELECT CAST(SettingValue AS INT) FROM dbo.Tr_Setting WHERE SettingKey='LeadMinInstruments')
    AND NOT EXISTS (SELECT 1 FROM trained t WHERE t.CustomerId=i.CustomerId)),
B AS (
  SELECT 'B' LeadType, CustomerId, CourseId,
         CONCAT(N'ใบประกาศ ',COUNT(*),N' คน หมดอายุ ',CONVERT(VARCHAR(10),MIN(CertExpireDate),23)) Reason,
         1000-DATEDIFF(DAY,CAST(GETDATE() AS DATE),MIN(CertExpireDate)) Score
  FROM dbo.v_Tr_CertStatus
  WHERE CertNo IS NOT NULL AND CertExpireDate BETWEEN DATEADD(DAY,-180,CAST(GETDATE() AS DATE)) AND DATEADD(DAY,90,CAST(GETDATE() AS DATE))
  GROUP BY CustomerId, CourseId),
C AS (
  SELECT DISTINCT 'C' LeadType, s.CustomerId, co.NextCourseId CourseId, CONCAT(N'เรียน ',co.CourseCode,N' แล้ว ต่อยอดได้') Reason, 50 Score
  FROM dbo.v_Tr_CertStatus s JOIN dbo.Tr_Course co ON co.CourseId=s.CourseId
  WHERE co.NextCourseId IS NOT NULL AND s.CertNo IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM dbo.v_Tr_CertStatus s2 WHERE s2.CustomerId=s.CustomerId AND s2.CourseId=co.NextCourseId))
SELECT l.*, f.FollowStatus, f.Note
FROM (SELECT * FROM A UNION ALL SELECT * FROM B UNION ALL SELECT * FROM C) l
LEFT JOIN dbo.Tr_LeadFollow f ON f.LeadType=l.LeadType AND f.CustomerId=l.CustomerId AND f.CourseId=l.CourseId;
GO

CREATE OR ALTER VIEW dbo.v_Tr_RevenueMonthly AS
SELECT YEAR(c.StartDate) Yr, MONTH(c.StartDate) Mo, g.Source,
       SUM(g.Amount) Revenue,
       SUM(CASE WHEN c.StartDate<=CAST(GETDATE() AS DATE) THEN g.Amount ELSE 0 END) Delivered,
       SUM(CASE WHEN c.StartDate> CAST(GETDATE() AS DATE) THEN g.Amount ELSE 0 END) Booked
FROM dbo.Tr_Registration g JOIN dbo.Tr_Class c ON c.ClassNo=g.ClassNo
WHERE c.Status<>'CANCEL'
GROUP BY YEAR(c.StartDate), MONTH(c.StartDate), g.Source;
GO

/* ---------- 5. Procedures ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_Tr_OpenClass
  @CourseId INT, @ClassType CHAR(1), @StartDate DATE, @Days TINYINT=1, @Venue NVARCHAR(200)=NULL,
  @TrainerId INT=NULL, @Seats SMALLINT=NULL, @Price DECIMAL(12,2)=NULL, @CustomerId VARCHAR(20)=NULL,
  @User NVARCHAR(50)=NULL, @ClassNo VARCHAR(20)=NULL OUTPUT
AS
BEGIN
  SET XACT_ABORT ON;
  DECLARE @yy CHAR(2)=RIGHT(CAST(YEAR(@StartDate) AS VARCHAR),2);
  BEGIN TRAN;
    SELECT @ClassNo='TR'+@yy+'-'+RIGHT('000'+CAST(ISNULL(MAX(CAST(SUBSTRING(ClassNo,6,3) AS INT)),0)+1 AS VARCHAR),3)
      FROM dbo.Tr_Class WITH (TABLOCKX) WHERE ClassNo LIKE 'TR'+@yy+'-%';
    INSERT dbo.Tr_Class(ClassNo,CourseId,ClassType,StartDate,Days,Venue,TrainerId,Seats,Price,CustomerId,CreatedBy)
    SELECT @ClassNo,@CourseId,@ClassType,@StartDate,@Days,@Venue,@TrainerId,ISNULL(@Seats,DefaultSeats),
           ISNULL(@Price,CASE WHEN @ClassType='I' THEN InhousePrice ELSE PublicPrice END),@CustomerId,@User
      FROM dbo.Tr_Course WHERE CourseId=@CourseId;
  COMMIT;
END
GO

/* ลงทะเบียน: @Names = JSON [{"name":"..","position":"..","email":".."}] */
CREATE OR ALTER PROCEDURE dbo.sp_Tr_Register
  @ClassNo VARCHAR(20), @CustomerId VARCHAR(20), @Names NVARCHAR(MAX), @Source VARCHAR(5)='TEAM',
  @ReferSaleName NVARCHAR(100)=NULL, @Amount DECIMAL(12,2)=NULL, @AllowOverbook BIT=0, @RegId INT=NULL OUTPUT
AS
BEGIN
  SET XACT_ABORT ON;
  DECLARE @n INT=(SELECT COUNT(*) FROM OPENJSON(@Names)), @seats SMALLINT, @type CHAR(1), @price DECIMAL(12,2), @pax INT;
  SELECT @seats=Seats,@type=ClassType,@price=Price FROM dbo.Tr_Class WHERE ClassNo=@ClassNo AND Status='OPEN';
  IF @seats IS NULL THROW 50101,N'รอบอบรมไม่เปิดรับ',1;
  SELECT @pax=COUNT(*) FROM dbo.Tr_Attendee x JOIN dbo.Tr_Registration g ON g.RegId=x.RegId WHERE g.ClassNo=@ClassNo;
  IF @type='P' AND @pax+@n>@seats AND @AllowOverbook=0 THROW 50102,N'ที่นั่งไม่พอ',1;
  BEGIN TRAN;
    INSERT dbo.Tr_Registration(ClassNo,CustomerId,Source,ReferSaleName,Amount)
    VALUES (@ClassNo,@CustomerId,@Source,@ReferSaleName,ISNULL(@Amount,CASE WHEN @type='P' THEN @price*@n ELSE @price END));
    SET @RegId=SCOPE_IDENTITY();
    INSERT dbo.Tr_Attendee(RegId,FullName,Position,Email)
    SELECT @RegId,j.name,j.position,j.email FROM OPENJSON(@Names) WITH (name NVARCHAR(150),position NVARCHAR(100),email VARCHAR(150)) j;
    /* ติดตามโอกาสที่ปิดได้ */
    UPDATE f SET FollowStatus='W', UpdatedAt=SYSDATETIME()
      FROM dbo.Tr_LeadFollow f JOIN dbo.Tr_Class c ON c.ClassNo=@ClassNo
     WHERE f.CustomerId=@CustomerId AND f.CourseId=c.CourseId;
  COMMIT;
END
GO

/* ออกใบประกาศให้ผู้ผ่าน (เข้าอบรม + คะแนน >= เกณฑ์) และปิดรอบเป็น DONE */
CREATE OR ALTER PROCEDURE dbo.sp_Tr_IssueCertificates @ClassNo VARCHAR(20)
AS
BEGIN
  SET XACT_ABORT ON;
  DECLARE @pass DECIMAL(5,1)=(SELECT CAST(SettingValue AS DECIMAL(5,1)) FROM dbo.Tr_Setting WHERE SettingKey='PassScore');
  DECLARE @end DATE, @valid TINYINT, @yy CHAR(2), @last INT;
  SELECT @end=c.EndDate, @valid=co.CertValidYears, @yy=RIGHT(CAST(YEAR(c.StartDate) AS VARCHAR),2)
    FROM dbo.Tr_Class c JOIN dbo.Tr_Course co ON co.CourseId=c.CourseId WHERE c.ClassNo=@ClassNo;
  BEGIN TRAN;
    SELECT @last=ISNULL(MAX(CAST(RIGHT(CertNo,5) AS INT)),0) FROM dbo.Tr_Attendee WITH (TABLOCKX) WHERE CertNo LIKE 'PCT'+@yy+'-%';
    WITH t AS (
      SELECT x.*, ROW_NUMBER() OVER (ORDER BY x.AttendeeId) rn
      FROM dbo.Tr_Attendee x JOIN dbo.Tr_Registration g ON g.RegId=x.RegId
      WHERE g.ClassNo=@ClassNo AND x.CertNo IS NULL AND x.Attended=1 AND x.Score>=@pass)
    UPDATE t SET CertNo='PCT'+@yy+'-'+RIGHT('00000'+CAST(@last+rn AS VARCHAR),5),
                 CertIssueDate=@end, CertExpireDate=DATEADD(YEAR,@valid,@end);
    UPDATE dbo.Tr_Class SET Status='DONE' WHERE ClassNo=@ClassNo AND Status='OPEN';
  COMMIT;
  SELECT x.FullName,x.CertNo,x.CertExpireDate FROM dbo.Tr_Attendee x JOIN dbo.Tr_Registration g ON g.RegId=x.RegId
   WHERE g.ClassNo=@ClassNo AND x.CertNo IS NOT NULL ORDER BY x.CertNo;
END
GO

/* ความคืบหน้าเป้าทีมอบรม: เป้า = รายได้ปีก่อน × (1 + TargetGrowthPct) */
CREATE OR ALTER PROCEDURE dbo.sp_Tr_TargetProgress @Year INT
AS
BEGIN
  DECLARE @g DECIMAL(6,2)=(SELECT CAST(SettingValue AS DECIMAL(6,2)) FROM dbo.Tr_Setting WHERE SettingKey='TargetGrowthPct')/100.0;
  SELECT m.Mo,
         ISNULL(SUM(CASE WHEN m.Yr=@Year-1 THEN m.Revenue END),0)*(1+@g) Target,
         ISNULL(SUM(CASE WHEN m.Yr=@Year THEN m.Delivered END),0) Delivered,
         ISNULL(SUM(CASE WHEN m.Yr=@Year THEN m.Booked END),0) Booked,
         ISNULL(SUM(CASE WHEN m.Yr=@Year AND m.Source='SALE' THEN m.Revenue END),0) FromCalSale
  FROM dbo.v_Tr_RevenueMonthly m WHERE m.Yr IN (@Year-1,@Year)
  GROUP BY m.Mo ORDER BY m.Mo;
END
GO

/* =====================================================================
   6. ทะเบียนวิทยากร · ต้นทุนต่อรอบ · แบบประเมินหลังอบรม (เพิ่ม 20 พ.ย. 2569)
   ===================================================================== */
IF COL_LENGTH('dbo.Tr_Trainer','TrainerType') IS NULL
  ALTER TABLE dbo.Tr_Trainer ADD TrainerType CHAR(1) NOT NULL CONSTRAINT DF_Tr_Trainer_Type DEFAULT 'I'
      CONSTRAINT CK_Tr_Trainer_Type CHECK (TrainerType IN ('I','E')),   -- ภายใน / ภายนอก
    Phone VARCHAR(30) NULL, Email VARCHAR(150) NULL;
GO
/* หลักสูตรที่อนุมัติให้สอน */
IF OBJECT_ID('dbo.Tr_TrainerCourse') IS NULL
CREATE TABLE dbo.Tr_TrainerCourse(
  TrainerId   INT NOT NULL REFERENCES dbo.Tr_Trainer(TrainerId),
  CourseId    INT NOT NULL REFERENCES dbo.Tr_Course(CourseId),
  ApprovedBy  NVARCHAR(50) NULL,
  ApprovedAt  DATE NULL,
  PRIMARY KEY (TrainerId, CourseId));
GO
/* คุณสมบัติ / หลักฐานความสามารถ */
IF OBJECT_ID('dbo.Tr_TrainerQualification') IS NULL
CREATE TABLE dbo.Tr_TrainerQualification(
  QualId      INT IDENTITY PRIMARY KEY,
  TrainerId   INT NOT NULL REFERENCES dbo.Tr_Trainer(TrainerId),
  QualName    NVARCHAR(250) NOT NULL,          -- ใบรับรอง, หลักสูตรที่ผ่าน, ประสบการณ์
  EvidenceNo  VARCHAR(50)  NULL,
  EvidenceFile NVARCHAR(400) NULL,             -- path ไฟล์สแกน
  ExpireDate  DATE NULL);
GO
/* ต้นทุนต่อรอบ: ค่าวิทยากรรวม, ห้อง, อื่นๆ = คงที่ · อาหาร/คน/วัน, เอกสาร/คน = ผันแปร */
IF COL_LENGTH('dbo.Tr_Class','CostTrainer') IS NULL
  ALTER TABLE dbo.Tr_Class ADD
    CostTrainer  DECIMAL(12,2) NOT NULL CONSTRAINT DF_Tr_Class_CT DEFAULT 0,
    CostVenue    DECIMAL(12,2) NOT NULL CONSTRAINT DF_Tr_Class_CV DEFAULT 0,
    CostFoodPPD  DECIMAL(12,2) NOT NULL CONSTRAINT DF_Tr_Class_CF DEFAULT 0,
    CostDocPP    DECIMAL(12,2) NOT NULL CONSTRAINT DF_Tr_Class_CD DEFAULT 0,
    CostOther    DECIMAL(12,2) NOT NULL CONSTRAINT DF_Tr_Class_CO DEFAULT 0;
GO
/* แบบประเมินหลังอบรม (1 ชุดต่อผู้เรียน) */
IF OBJECT_ID('dbo.Tr_Evaluation') IS NULL
CREATE TABLE dbo.Tr_Evaluation(
  AttendeeId     INT NOT NULL PRIMARY KEY REFERENCES dbo.Tr_Attendee(AttendeeId) ON DELETE CASCADE,
  ScoreContent   TINYINT NOT NULL CHECK (ScoreContent BETWEEN 1 AND 5),
  ScoreTrainer   TINYINT NOT NULL CHECK (ScoreTrainer BETWEEN 1 AND 5),
  ScoreVenue     TINYINT NOT NULL CHECK (ScoreVenue BETWEEN 1 AND 5),
  Interest       VARCHAR(3) NOT NULL DEFAULT '' CHECK (Interest IN ('','IH','CAL')),  -- In-house / บริการสอบเทียบ
  Comment        NVARCHAR(1000) NULL,
  SubmittedAt    DATETIME2(0) NOT NULL DEFAULT SYSDATETIME());
GO

/* การเงินต่อรอบ + จุดคุ้มทุน */
CREATE OR ALTER VIEW dbo.v_Tr_ClassFinance AS
SELECT c.ClassNo,c.StartDate,c.ClassType,c.Status,c.Price,s.Pax,s.Revenue,
       c.CostTrainer+c.CostVenue+c.CostOther FixedCost,
       c.CostFoodPPD*c.Days+c.CostDocPP VarCostPerPax,
       CASE WHEN c.Status='CANCEL' THEN 0 ELSE c.CostTrainer+c.CostVenue+c.CostOther+s.Pax*(c.CostFoodPPD*c.Days+c.CostDocPP) END TotalCost,
       s.Revenue-CASE WHEN c.Status='CANCEL' THEN 0 ELSE c.CostTrainer+c.CostVenue+c.CostOther+s.Pax*(c.CostFoodPPD*c.Days+c.CostDocPP) END Profit,
       CASE WHEN c.ClassType='P' AND c.Price>c.CostFoodPPD*c.Days+c.CostDocPP
            THEN CEILING((c.CostTrainer+c.CostVenue+c.CostOther)/(c.Price-(c.CostFoodPPD*c.Days+c.CostDocPP))) END BreakEvenPax
FROM dbo.Tr_Class c JOIN dbo.v_Tr_ClassSummary s ON s.ClassNo=c.ClassNo;
GO

/* เตือนวิทยากร: ไม่ได้อนุมัติหลักสูตร / คุณสมบัติหมดอายุก่อนวันอบรม / ตารางชน */
CREATE OR ALTER VIEW dbo.v_Tr_TrainerWarning AS
SELECT c.ClassNo,c.StartDate,c.TrainerId,'NOT_APPROVED' WarnType,CAST(NULL AS VARCHAR(20)) OtherClassNo
FROM dbo.Tr_Class c
WHERE c.Status='OPEN' AND c.TrainerId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.Tr_TrainerCourse tc WHERE tc.TrainerId=c.TrainerId AND tc.CourseId=c.CourseId)
UNION ALL
SELECT c.ClassNo,c.StartDate,c.TrainerId,'QUAL_EXPIRED',NULL
FROM dbo.Tr_Class c
WHERE c.Status='OPEN' AND EXISTS (SELECT 1 FROM dbo.Tr_TrainerQualification q WHERE q.TrainerId=c.TrainerId AND q.ExpireDate<c.StartDate)
UNION ALL
SELECT a.ClassNo,a.StartDate,a.TrainerId,'CONFLICT',b.ClassNo
FROM dbo.Tr_Class a JOIN dbo.Tr_Class b
  ON b.TrainerId=a.TrainerId AND b.ClassNo<>a.ClassNo AND b.Status<>'CANCEL'
 AND a.StartDate<=b.EndDate AND b.StartDate<=a.EndDate
WHERE a.Status='OPEN';
GO

/* ผลงานวิทยากร 12 เดือน */
CREATE OR ALTER VIEW dbo.v_Tr_TrainerPerformance AS
WITH cls AS (
  SELECT c.TrainerId, c.ClassNo, co.Hours, f.Revenue
  FROM dbo.Tr_Class c JOIN dbo.Tr_Course co ON co.CourseId=c.CourseId
  JOIN dbo.v_Tr_ClassFinance f ON f.ClassNo=c.ClassNo
  WHERE c.Status='DONE' AND c.StartDate>DATEADD(DAY,-365,CAST(GETDATE() AS DATE))),
ev AS (
  SELECT cls.TrainerId, AVG(CAST(e.ScoreTrainer AS DECIMAL(5,2))) AvgScore, COUNT(*) N
  FROM cls JOIN dbo.Tr_Registration g ON g.ClassNo=cls.ClassNo
  JOIN dbo.Tr_Attendee x ON x.RegId=g.RegId JOIN dbo.Tr_Evaluation e ON e.AttendeeId=x.AttendeeId
  GROUP BY cls.TrainerId)
SELECT t.TrainerId,t.TrainerName,t.TrainerType,t.FeePerDay,
       ISNULL(k.Classes,0) Classes12m, ISNULL(k.Hours,0) Hours12m, ISNULL(k.Revenue,0) Revenue12m,
       CAST(ev.AvgScore AS DECIMAL(4,2)) AvgTrainerScore, ISNULL(ev.N,0) Evaluations
FROM dbo.Tr_Trainer t
LEFT JOIN (SELECT TrainerId, COUNT(*) Classes, SUM(Hours) Hours, SUM(Revenue) Revenue FROM cls GROUP BY TrainerId) k ON k.TrainerId=t.TrainerId
LEFT JOIN ev ON ev.TrainerId=t.TrainerId;
GO

/* ลูกค้าเป้าหมายกลุ่ม D: ผู้เรียนสนใจ In-house หรือบริการสอบเทียบ (12 เดือน) */
CREATE OR ALTER VIEW dbo.v_Tr_LeadsFromEvaluation AS
SELECT 'D' LeadType, g.CustomerId,
       CASE WHEN e.Interest='IH' THEN c.CourseId ELSE -1 END CourseId,
       e.Interest, COUNT(*) People, MAX(c.StartDate) LastClass
FROM dbo.Tr_Evaluation e
JOIN dbo.Tr_Attendee x ON x.AttendeeId=e.AttendeeId
JOIN dbo.Tr_Registration g ON g.RegId=x.RegId
JOIN dbo.Tr_Class c ON c.ClassNo=g.ClassNo
WHERE e.Interest<>'' AND c.StartDate>DATEADD(DAY,-365,CAST(GETDATE() AS DATE))
GROUP BY g.CustomerId, CASE WHEN e.Interest='IH' THEN c.CourseId ELSE -1 END, e.Interest;
GO
