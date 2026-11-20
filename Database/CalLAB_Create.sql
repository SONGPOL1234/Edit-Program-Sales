/* =====================================================================
   CalLAB — empty database generated from CalLAB_Schema_Atlas.html
   SQL Server. Structure only: no rows, no views, no procedures.
   Primary keys and NOT NULL / IDENTITY flags come from the atlas.
   Foreign keys: only the 2 declared relationships
     QuotationItem.QuotationNo  -> Quotation.QuotationNo
     QuotationRemark.QuotationNo -> Quotation.QuotationNo
   Quotation.QuotationNo is not a primary key in the atlas, so a UNIQUE
   constraint is added so those two foreign keys are legal.
   Inferred name matches are not created as foreign keys.
   ===================================================================== */
SET NOCOUNT ON;
GO

IF DB_ID(N'CalLAB') IS NULL
    CREATE DATABASE [CalLAB];
GO
USE [CalLAB];
GO

IF OBJECT_ID(N'dbo.[Paste Errors]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Paste Errors] (
        [Field0] NTEXT NULL,
        [Field1] NTEXT NULL,
        [Field2] NTEXT NULL,
        [Field3] NTEXT NULL,
        [Field4] NTEXT NULL,
        [Field5] NTEXT NULL,
        [Field6] NTEXT NULL,
        [Field7] NTEXT NULL,
        [Field8] NTEXT NULL,
        [Field9] NTEXT NULL,
        [Field10] NTEXT NULL,
        [Field11] NTEXT NULL,
        [Field12] NTEXT NULL,
        [Field13] NTEXT NULL,
        [Field14] NTEXT NULL,
        [Field15] NTEXT NULL,
        [Field16] NTEXT NULL,
        [Field17] NTEXT NULL,
        [Field18] NTEXT NULL,
        [Field19] NTEXT NULL,
        [Field20] NTEXT NULL,
        [Field21] NTEXT NULL,
        [Field22] NTEXT NULL,
        [Field23] NTEXT NULL,
        [Field24] NTEXT NULL,
        [Field25] NTEXT NULL,
        [Field26] NTEXT NULL,
        [Field27] NTEXT NULL,
        [Field28] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Groups]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Groups] (
        [Headgroup] NVARCHAR(3) NULL,
        [Nameheadgroup] NVARCHAR(80) NULL,
        [Chacks] NVARCHAR(1) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblSubContact]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblSubContact] (
        [SubContNo] NVARCHAR(15) NOT NULL,
        [ReceiveNo] NVARCHAR(15) NOT NULL,
        [SuppID] NVARCHAR(15) NOT NULL,
        [Date_out] DATETIME NOT NULL,
        [Date_expreceive] DATETIME NOT NULL,
        [Date_receive] DATETIME NULL,
        [ContactName] NVARCHAR(100) NULL,
        [DeliveryName] NVARCHAR(100) NOT NULL,
        [Status] NVARCHAR(50) NOT NULL,
        [TypeSub] BIT NOT NULL,
        [TypeCert] BIT NOT NULL,
        [TypeRepair] BIT NOT NULL,
        [CertType] NVARCHAR(50) NOT NULL,
        [IssueOwner] BIT NOT NULL,
        [Remarks] NVARCHAR(1000) NULL,
        [StdType] BIT NOT NULL,
        CONSTRAINT [PK_tblSubContact] PRIMARY KEY ([SubContNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[PassWord]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[PassWord] (
        [PassID] INT IDENTITY(1,1) NOT NULL,
        [PassName] NVARCHAR(70) NULL,
        [Password] NVARCHAR(40) NULL,
        [Level] INT NULL,
        [TechID] NVARCHAR(5) NOT NULL,
        CONSTRAINT [PK_PassWord] PRIMARY KEY ([PassID])
    );
END
GO

IF OBJECT_ID(N'dbo.[FunctionName]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[FunctionName] (
        [FunctionName] NVARCHAR(50) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Acces]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Acces] (
        [CalCode] NVARCHAR(15) NULL,
        [AssetNo] NVARCHAR(50) NULL,
        [Descrip] NVARCHAR(150) NULL,
        [Manu] NVARCHAR(150) NULL,
        [Mode] NVARCHAR(80) NULL,
        [SerialCode] NVARCHAR(15) NULL,
        [Qty] INT NULL,
        [Man] BIT NOT NULL,
        [Acc] BIT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Description]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Description] (
        [DescriptionId] NVARCHAR(9) NOT NULL,
        [DescriptionName] NVARCHAR(255) NULL,
        [Price] MONEY NULL,
        [DescriptionStatus] BIT NOT NULL,
        CONSTRAINT [PK_Description] PRIMARY KEY ([DescriptionId])
    );
END
GO

IF OBJECT_ID(N'dbo.[Pass]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Pass] (
        [Password] NVARCHAR(50) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Workorder]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Workorder] (
        [ItemOrder] NVARCHAR(2) NULL,
        [OrderNo] NVARCHAR(15) NULL,
        [WorkOrder] NVARCHAR(15) NULL,
        [TechId] NVARCHAR(90) NULL,
        [DateIssue] NVARCHAR(10) NULL,
        [StartDate] NVARCHAR(10) NULL,
        [FinishDate] NVARCHAR(10) NULL,
        [Status] NVARCHAR(50) NULL,
        [TotalH] FLOAT NULL,
        [RH] FLOAT NULL,
        [ProcH] FLOAT NULL,
        [Pass] BIT NOT NULL,
        [Fail] BIT NOT NULL,
        [Ref] NVARCHAR(150) NULL,
        [Note] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Customer]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Customer] (
        [CustomerID] NVARCHAR(15) NOT NULL,
        [CustomerNo] NVARCHAR(25) NULL,
        [CustomerName] NVARCHAR(120) NULL,
        [CustomerNameEng] NVARCHAR(120) NULL,
        [Address] NVARCHAR(255) NULL,
        [AddressEng] NVARCHAR(255) NULL,
        [PhoneNo] NVARCHAR(55) NULL,
        [FaxNo] NVARCHAR(55) NULL,
        [ContactName] NVARCHAR(80) NULL,
        [ClientType] NVARCHAR(15) NULL,
        [Prefix] NVARCHAR(10) NULL,
        [Position] NVARCHAR(60) NULL,
        [Department] NVARCHAR(100) NULL,
        [Note] NTEXT NULL,
        [TaxNo] NVARCHAR(25) NULL,
        [BranchName] NVARCHAR(150) NULL,
        [Condition1] NVARCHAR(250) NULL,
        [Condition2] NVARCHAR(250) NULL,
        [ConditionFile] NVARCHAR(250) NULL,
        [CustomerType] NVARCHAR(15) NOT NULL,
        [CustomerStatus] BIT NOT NULL,
        [ListOfBill] NVARCHAR(150) NOT NULL,
        [ListOfCheque] NVARCHAR(150) NOT NULL,
        [CustomerWebsite] NVARCHAR(80) NOT NULL,
        [CustomerEmail] NVARCHAR(80) NOT NULL,
        [RequestTechData] NVARCHAR(250) NOT NULL,
        [AddressAccount] NVARCHAR(255) NULL,
        [PaymentQuo] NVARCHAR(150) NULL,
        [TechId] NVARCHAR(5) NOT NULL,
        [Map] NVARCHAR(150) NOT NULL,
        [DiscountP] FLOAT NOT NULL,
        [ConfirmOrder] NVARCHAR(50) NOT NULL,
        [DeliveryBy] NVARCHAR(50) NOT NULL,
        [CreditCash] BIT NOT NULL,
        [CreditCredit] BIT NOT NULL,
        [CreditCheque] BIT NOT NULL,
        [PaybyCash] BIT NOT NULL,
        [PaybyCheque] BIT NOT NULL,
        [PaybyBankTransfer] BIT NOT NULL,
        [Bankname] NVARCHAR(80) NOT NULL,
        [BankID] NVARCHAR(20) NOT NULL,
        [QualitySystem1] BIT NOT NULL,
        [QualitySystem2] BIT NOT NULL,
        [QualitySystem3] BIT NOT NULL,
        [QualitySystem4] BIT NOT NULL,
        [QualitySystem5] BIT NOT NULL,
        [QualitySystem6] BIT NOT NULL,
        [QualitySystem7] BIT NOT NULL,
        [QualitySystem8] BIT NOT NULL,
        [QualitySystem9] BIT NOT NULL,
        [QualitySystem10] BIT NOT NULL,
        [QualitySystem11] BIT NOT NULL,
        [QualitySystem12] BIT NOT NULL,
        [QualityRemark] NVARCHAR(150) NOT NULL,
        [QualityFile] NVARCHAR(150) NOT NULL,
        CONSTRAINT [PK_Customer] PRIMARY KEY ([CustomerID])
    );
END
GO

IF OBJECT_ID(N'dbo.[Stands]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Stands] (
        [CalCode] NVARCHAR(15) NULL,
        [InvenNo] NVARCHAR(20) NULL,
        [Traceble] NVARCHAR(150) NULL,
        [TracebleRef] NVARCHAR(150) NULL,
        [ServiceDate] NVARCHAR(10) NULL,
        [EndService] NVARCHAR(10) NULL,
        [CertNo] NVARCHAR(55) NULL,
        [SerialNo] NVARCHAR(30) NULL,
        [DescriptionId] NVARCHAR(8) NULL,
        [Manuf] NVARCHAR(100) NULL,
        [Model] NVARCHAR(100) NULL,
        [Range] NVARCHAR(150) NULL,
        [Type] NVARCHAR(80) NULL,
        [Access] BIT NOT NULL,
        [DateDue] NVARCHAR(10) NULL,
        [NextCal] NVARCHAR(10) NULL,
        [Note] NTEXT NULL,
        [CalDate] NVARCHAR(10) NULL,
        [Interval] NVARCHAR(15) NULL,
        [IntervalM] NVARCHAR(15) NULL,
        [DelNo] NVARCHAR(15) NULL,
        [Status] NVARCHAR(15) NULL,
        [SendBy] NVARCHAR(50) NULL,
        [Remark] NTEXT NULL,
        [SendDate] NVARCHAR(10) NULL,
        [CustomerId] NVARCHAR(15) NULL,
        [IntervalAlarm] INT NULL,
        [StandStatus] BIT NOT NULL,
        [StatusRepair] BIT NOT NULL,
        [StatusSendCal] BIT NOT NULL,
        [StatusCalFinish] BIT NOT NULL,
        [ANAB_17025] BIT NOT NULL,
        [TISI_17025] BIT NOT NULL,
        [ServiceType] NVARCHAR(2) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[QuotationItem]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[QuotationItem] (
        [QuotationID] INT NOT NULL,
        [QuotationNo] NVARCHAR(20) NOT NULL,
        [Item] NVARCHAR(6) NULL,
        [Description] NVARCHAR(150) NULL,
        [SerialNo] NVARCHAR(30) NULL,
        [Manuf] NVARCHAR(150) NULL,
        [Model] NVARCHAR(100) NULL,
        [Unit] NVARCHAR(15) NULL,
        [Range] NVARCHAR(150) NULL,
        [Qty] INT NULL,
        [UDiscount] MONEY NULL,
        [UPrice] MONEY NULL,
        [TPrice] MONEY NULL,
        [Check] BIT NOT NULL,
        [Remark] NTEXT NULL,
        [DescriptionId] NVARCHAR(8) NULL,
        [Chk17025] BIT NOT NULL,
        [ChkSub] INT NOT NULL,
        [Chk17025_ANAB] BIT NOT NULL,
        [ChkCert] BIT NOT NULL,
        [Status] NVARCHAR(80) NOT NULL,
        [PONo] NVARCHAR(50) NOT NULL,
        [PODate] DATETIME NULL,
        [INVNo] NVARCHAR(50) NOT NULL,
        [INVDate] DATETIME NULL,
        [Forcast] DATETIME NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblSubContactList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblSubContactList] (
        [SubContNo] NVARCHAR(15) NOT NULL,
        [ItemNo] SMALLINT NULL,
        [OrderNo] NVARCHAR(15) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Report]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Report] (
        [ReportNo] NVARCHAR(15) NOT NULL,
        [ReportName] NVARCHAR(120) NULL,
        [Revision] NVARCHAR(50) NULL,
        [RevisionDate] NVARCHAR(10) NULL,
        [ReportPath] NVARCHAR(120) NULL,
        [Technical] NTEXT NULL,
        CONSTRAINT [PK_Report] PRIMARY KEY ([ReportNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPOList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPOList] (
        [PONo] NVARCHAR(10) NULL,
        [ItemNo] SMALLINT NULL,
        [Description] NVARCHAR(400) NULL,
        [Qty] INT NULL,
        [Price] FLOAT NULL,
        [Unit] NVARCHAR(25) NULL,
        [ExpCode] NVARCHAR(15) NOT NULL,
        [Manuf] NVARCHAR(150) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[QuotationCost]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[QuotationCost] (
        [QuotationNo] NVARCHAR(20) NOT NULL,
        [CDOnsiteDate] DATETIME NULL,
        [CDOnsiteArea] NVARCHAR(150) NOT NULL,
        [CDEngineerCostDay] FLOAT NOT NULL,
        [CDLeadCostDay] FLOAT NOT NULL,
        [CDOilCostKm] FLOAT NOT NULL,
        [CDTransCostTrip] FLOAT NOT NULL,
        [CDHotelCostDay] FLOAT NOT NULL,
        [CDEngineerStaff] INT NOT NULL,
        [CDLeadStaff] INT NOT NULL,
        [CDOilKm] INT NOT NULL,
        [CDTransTrip] INT NOT NULL,
        [CDHotelDay] INT NOT NULL,
        [CDEngineerCost] FLOAT NOT NULL,
        [CDLeadCost] FLOAT NOT NULL,
        [CDOilCost] FLOAT NOT NULL,
        [CDTransport] NVARCHAR(150) NOT NULL,
        [CDHotel] NVARCHAR(150) NOT NULL,
        [CDComm] FLOAT NOT NULL,
        [CDSubContract] FLOAT NOT NULL,
        [CDTotalCost] FLOAT NOT NULL,
        [CDOthers] FLOAT NOT NULL,
        [CDRemarks] NVARCHAR(250) NOT NULL,
        [PDCost] FLOAT NOT NULL,
        [PDComm] FLOAT NOT NULL,
        [PDVat] FLOAT NOT NULL,
        [PDOhers] FLOAT NOT NULL,
        [PDTotalCost] FLOAT NOT NULL,
        [PDRemarks] NVARCHAR(250) NOT NULL,
        CONSTRAINT [PK_QuotationCost] PRIMARY KEY ([QuotationNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPO]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPO] (
        [PONo] NVARCHAR(10) NOT NULL,
        [Date_out] DATETIME NULL,
        [SuppID] NVARCHAR(15) NULL,
        [Vat] INT NULL,
        [VatPrice] FLOAT NULL,
        [TotalPrice] FLOAT NULL,
        [GrandTotalPrice] FLOAT NULL,
        [PRNo] NVARCHAR(40) NULL,
        [QuantationNo] NVARCHAR(30) NULL,
        [Discount] FLOAT NULL,
        [PaymentCash] BIT NOT NULL,
        [PaymentCredit] BIT NOT NULL,
        [PaymentTerm] NVARCHAR(90) NULL,
        [ManagementID] NVARCHAR(5) NOT NULL,
        [Date_Management] DATETIME NULL,
        CONSTRAINT [PK_tblPO] PRIMARY KEY ([PONo])
    );
END
GO

IF OBJECT_ID(N'dbo.[QuotationRemark]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[QuotationRemark] (
        [QuotationID] INT NULL,
        [QuotationNo] NVARCHAR(20) NULL,
        [ItemRemark] SMALLINT NULL,
        [DateRemark] DATETIME NULL,
        [ByRemark] NVARCHAR(80) NULL,
        [NoteRemark] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPRList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPRList] (
        [PRNo] NVARCHAR(10) NULL,
        [ItemNo] SMALLINT NULL,
        [Description] NVARCHAR(400) NULL,
        [Qty] INT NULL,
        [Price] FLOAT NULL,
        [Unit] NVARCHAR(25) NULL,
        [Discount] FLOAT NULL,
        [TotalPrice] FLOAT NULL,
        [ExpCode] NVARCHAR(15) NOT NULL,
        [Manuf] NVARCHAR(150) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tbEducation]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tbEducation] (
        [TechId] NVARCHAR(5) NULL,
        [ItemEducation] INT NULL,
        [Course] NVARCHAR(120) NULL,
        [Department] NVARCHAR(200) NULL,
        [Institution] NVARCHAR(150) NULL,
        [Grade] NVARCHAR(200) NULL,
        [YearEnd] NVARCHAR(30) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Quotation]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Quotation] (
        [QuotationID] INT IDENTITY(1,1) NOT NULL,
        [Item] NVARCHAR(6) NULL,
        [ReceiveDate] NVARCHAR(10) NULL,
        [RequestNo] NVARCHAR(50) NULL,
        [Company] NVARCHAR(15) NULL,
        [Subject] NVARCHAR(150) NULL,
        [QuotationType] NVARCHAR(30) NULL,
        [QuotationNo] NVARCHAR(20) NULL,
        [SubmitDate] NVARCHAR(10) NULL,
        [InquiryDate] DATETIME NULL,
        [Qprice] FLOAT NULL,
        [Currency] NVARCHAR(10) NULL,
        [EngBy] NVARCHAR(90) NULL,
        [OrderNo] NVARCHAR(20) NULL,
        [OrderReceive] INT NULL,
        [Revision] INT NULL,
        [StatusQ] NVARCHAR(50) NULL,
        [Remark] NVARCHAR(550) NOT NULL,
        [Project] NVARCHAR(200) NULL,
        [Payment] NVARCHAR(150) NULL,
        [DueDate] NVARCHAR(150) NULL,
        [Duration] NVARCHAR(150) NULL,
        [Scope] NTEXT NULL,
        [Document] NTEXT NULL,
        [Validity] NTEXT NULL,
        [Name] NVARCHAR(120) NULL,
        [NameCustomer] NVARCHAR(120) NULL,
        [Note] NTEXT NULL,
        [Reference] NVARCHAR(150) NULL,
        [ChkDiscount] BIT NOT NULL,
        [Discount] FLOAT NULL,
        [ComName] NVARCHAR(80) NULL,
        [ComTel] NVARCHAR(50) NULL,
        [ComRate] INT NULL,
        [Commission] BIT NOT NULL,
        [ReportName] NVARCHAR(250) NULL,
        [CommercialID] NVARCHAR(5) NULL,
        [TechnicalID] NVARCHAR(5) NULL,
        [PaymentTerm] BIT NOT NULL,
        [AddressOffice] INT NULL,
        [PONo] NVARCHAR(250) NOT NULL,
        [PODate] DATETIME NULL,
        [chkRecall] BIT NOT NULL,
        [chkRef] BIT NOT NULL,
        [PriceValidity] NVARCHAR(20) NOT NULL,
        [DeliveryDate] NVARCHAR(20) NOT NULL,
        [DeliveryTo] NVARCHAR(150) NOT NULL,
        [ChequePost] BIT NOT NULL,
        [AttachPOFileName] NVARCHAR(200) NOT NULL,
        [AttachCNFileName] NVARCHAR(200) NOT NULL,
        [INVList] NVARCHAR(200) NOT NULL,
        CONSTRAINT [PK_Quotation] PRIMARY KEY ([QuotationID])
    );
END
GO

IF OBJECT_ID(N'dbo.[CheckList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[CheckList] (
        [CalCode] NVARCHAR(15) NULL,
        [Suitable] BIT NOT NULL,
        [CheckName] NVARCHAR(50) NULL,
        [CheckDate] DATETIME NULL,
        [DispatchName] NVARCHAR(50) NULL,
        [DispatchDate] DATETIME NULL,
        [Note] NTEXT NULL,
        [Note1] NTEXT NULL,
        [Remarks] NTEXT NULL,
        [IssueNo] NVARCHAR(1) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Traning]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Traning] (
        [TechId] NVARCHAR(5) NULL,
        [DateTran] NVARCHAR(10) NULL,
        [Course] NVARCHAR(120) NULL,
        [Instructor] NVARCHAR(200) NULL,
        [Institution] NVARCHAR(150) NULL,
        [Description] NVARCHAR(200) NULL,
        [TranHours] INT NULL,
        [CreditHours] INT NULL,
        [Cost] MONEY NULL,
        [Remark] NTEXT NULL,
        [PathDocument] NVARCHAR(250) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblInvoiceList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblInvoiceList] (
        [InvoiceNo] NVARCHAR(15) NULL,
        [ItemNo] INT NULL,
        [OrderNo] NVARCHAR(20) NULL,
        [Qty] SMALLINT NULL,
        [Price] FLOAT NULL,
        [Unit] NVARCHAR(25) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Accessories]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Accessories] (
        [CalCode] NVARCHAR(15) NULL,
        [Scope] NVARCHAR(50) NULL,
        [Found] BIT NOT NULL,
        [Left] BIT NOT NULL,
        [Na] BIT NOT NULL,
        [Remarks] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblInvoiceItem]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblInvoiceItem] (
        [InvoiceNo] NVARCHAR(15) NULL,
        [ItemNo] INT NULL,
        [Description] NVARCHAR(150) NULL,
        [Manuf] NVARCHAR(150) NULL,
        [Model] NVARCHAR(100) NULL,
        [Unit] NVARCHAR(15) NULL,
        [Range] NVARCHAR(150) NULL,
        [Qty] INT NULL,
        [UDiscount] MONEY NULL,
        [UPrice] MONEY NULL,
        [TPrice] MONEY NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Manufac]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Manufac] (
        [Manuf] NVARCHAR(150) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblInvoice]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblInvoice] (
        [InvoiceNo] NVARCHAR(15) NULL,
        [Date_out] DATETIME NULL,
        [CustomerID] NVARCHAR(15) NULL,
        [DiscountPrice] FLOAT NULL,
        [Vat] INT NULL,
        [VatPrice] FLOAT NULL,
        [TotalPrice] FLOAT NULL,
        [GrandTotalPrice] FLOAT NULL,
        [Cash] BIT NOT NULL,
        [Cheque] BIT NOT NULL,
        [Others] BIT NOT NULL,
        [OtherName] NVARCHAR(50) NULL,
        [ChequeNo] NVARCHAR(20) NULL,
        [ChequeDate] DATETIME NULL,
        [BankName] NVARCHAR(50) NULL,
        [BranchName] NVARCHAR(50) NULL,
        [ChequeCost] FLOAT NULL,
        [Note] NVARCHAR(150) NULL,
        [RefNo] NVARCHAR(150) NULL,
        [Subject] NVARCHAR(150) NULL,
        [ChkDiscountUnit] BIT NOT NULL,
        [WHTax] FLOAT NULL,
        [WHTaxPrice] FLOAT NULL,
        [Transfers] BIT NOT NULL,
        [PayMoney] BIT NOT NULL,
        [DisableInv] BIT NOT NULL,
        [AccSignID] NVARCHAR(5) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblTMSetting]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblTMSetting] (
        [TM_Loc] NVARCHAR(20) NOT NULL,
        [DueDay] INT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[History]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[History] (
        [CertNo] NVARCHAR(15) NOT NULL,
        [History_No] NVARCHAR(10) NULL,
        [CustomerID] NVARCHAR(15) NULL,
        [TechID] NVARCHAR(15) NULL,
        [AdminID] NVARCHAR(15) NULL,
        [Location] NVARCHAR(125) NULL,
        [Method] NVARCHAR(90) NULL,
        [Temp] NVARCHAR(25) NOT NULL,
        [TempB] FLOAT NULL,
        [TempL] INT NULL,
        [Rh] NVARCHAR(25) NOT NULL,
        [RhB] FLOAT NULL,
        [RhL] INT NULL,
        [RepairCost] MONEY NULL,
        [CalCost] MONEY NULL,
        [CalDate] NVARCHAR(10) NULL,
        [NextDate] NVARCHAR(10) NULL,
        [DateIssue] NVARCHAR(10) NULL,
        [PageNum] INT NULL,
        [OrderNo] NVARCHAR(15) NULL,
        [Head] NVARCHAR(100) NULL,
        [ReportID] NVARCHAR(15) NULL,
        [ProcedureID] NVARCHAR(150) NULL,
        [ProcedureUse] NTEXT NULL,
        [ServiceLocationType] BIT NOT NULL,
        [ConditionType] BIT NOT NULL,
        [ManualType] BIT NOT NULL,
        [CalResult] NVARCHAR(150) NULL,
        [LabName] NVARCHAR(4) NOT NULL,
        CONSTRAINT [PK_History] PRIMARY KEY ([CertNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[OrderConfirm]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[OrderConfirm] (
        [QuotationID] INT NULL,
        [QuotationNo] NVARCHAR(20) NULL,
        [Item] NVARCHAR(6) NULL,
        [Description] NVARCHAR(150) NULL,
        [Manuf] NVARCHAR(150) NULL,
        [Model] NVARCHAR(100) NULL,
        [Unit] NVARCHAR(15) NULL,
        [Range] NVARCHAR(150) NULL,
        [Qty] INT NULL,
        [UDiscount] MONEY NULL,
        [UPrice] MONEY NULL,
        [TPrice] MONEY NULL,
        [Check] BIT NOT NULL,
        [Remark] NTEXT NULL,
        [PoNo] NVARCHAR(20) NULL,
        [PoDate] NVARCHAR(10) NULL,
        [Invoice] NVARCHAR(20) NULL,
        [InvoiceDate] NVARCHAR(10) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[JobNumber]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[JobNumber] (
        [JobNo] NVARCHAR(20) NULL,
        [JobName] NVARCHAR(120) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Instrument]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Instrument] (
        [OrderNo] NVARCHAR(15) NOT NULL,
        [ReceiveNo] NVARCHAR(15) NULL,
        [IssueNo] NVARCHAR(15) NULL,
        [SerialNo] NVARCHAR(100) NULL,
        [AssetNo] NVARCHAR(100) NULL,
        [DescriptionName] NVARCHAR(9) NULL,
        [Manuf] NVARCHAR(100) NULL,
        [Accessorie] NVARCHAR(150) NULL,
        [Access] BIT NOT NULL,
        [Model] NVARCHAR(100) NULL,
        [Rang] NVARCHAR(220) NULL,
        [Servicetype] NVARCHAR(100) NULL,
        [Type] NVARCHAR(80) NULL,
        [Uncertainly] NVARCHAR(200) NULL,
        [CalLab] NVARCHAR(15) NULL,
        [CustomerID] NVARCHAR(15) NULL,
        [Compleate] BIT NOT NULL,
        [FinishDate] NVARCHAR(10) NULL,
        [NextDate] NVARCHAR(10) NULL,
        [ReceiveDate] NVARCHAR(10) NULL,
        [IssueDate] NVARCHAR(10) NULL,
        [InactiveDate] NVARCHAR(10) NULL,
        [ReceiveTime] DATETIME NULL,
        [ReceiveBy] NVARCHAR(80) NULL,
        [IssueBy] NVARCHAR(80) NULL,
        [ComebackBy] NVARCHAR(80) NULL,
        [SendbackBy] NVARCHAR(80) NULL,
        [Testpoint] NVARCHAR(200) NULL,
        [CustomerRef] NVARCHAR(400) NULL,
        [SparePart] MONEY NULL,
        [CalValue] INT NULL,
        [CalCost1] MONEY NULL,
        [CalCost] MONEY NULL,
        [CalHrs] INT NULL,
        [CalInterval] INT NULL,
        [CertNo] NVARCHAR(15) NULL,
        [ProcedureNo] NVARCHAR(150) NULL,
        [Status] NVARCHAR(20) NULL,
        [Status1] NVARCHAR(30) NULL,
        [Remark] NVARCHAR(150) NULL,
        [Note] NVARCHAR(150) NULL,
        [MainDate] NVARCHAR(10) NULL,
        [NextMain] NVARCHAR(10) NULL,
        [Expect] NVARCHAR(10) NULL,
        [QuotationNo] NVARCHAR(20) NULL,
        [PoNo] NVARCHAR(30) NULL,
        [PoDate] NVARCHAR(10) NULL,
        [Invoice] NVARCHAR(30) NULL,
        [InvoiceDate] NVARCHAR(10) NULL,
        [LabNo] NVARCHAR(2) NOT NULL,
        [ReportNo] NVARCHAR(15) NULL,
        [ReportPath] NVARCHAR(255) NULL,
        [Unit] NVARCHAR(50) NULL,
        [TermPayment] NVARCHAR(120) NULL,
        [DueDate] DATETIME NULL,
        [AddressOffice] INT NULL,
        [AccType] NVARCHAR(10) NULL,
        [CertLocation] NVARCHAR(150) NOT NULL,
        [CustomerIDCert] NVARCHAR(15) NULL,
        [UrgentCase] BIT NOT NULL,
        [ReturnCert] BIT NOT NULL,
        [Chk17025] BIT NOT NULL,
        [Chk17025_ANAB] BIT NOT NULL,
        [QuotationNoNew] NVARCHAR(20) NOT NULL,
        [Status_DT] DATETIME NULL,
        CONSTRAINT [PK_Instrument] PRIMARY KEY ([OrderNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[HistoryStand]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[HistoryStand] (
        [CertNo] NVARCHAR(15) NULL,
        [History_No] NVARCHAR(10) NULL,
        [StandID] NVARCHAR(15) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPaymentV]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPaymentV] (
        [PaymentNo] NVARCHAR(15) NOT NULL,
        [Date_out] DATETIME NOT NULL,
        [Subject] NVARCHAR(150) NOT NULL,
        [SuppID] NVARCHAR(15) NOT NULL,
        [TotalPrice] FLOAT NOT NULL,
        [GrandTotalPrice] FLOAT NOT NULL,
        [Cash] BIT NOT NULL,
        [Cheque] BIT NOT NULL,
        [Transfers] BIT NOT NULL,
        [Others] BIT NOT NULL,
        [OtherName] NVARCHAR(50) NOT NULL,
        [ChequeNo] NVARCHAR(20) NOT NULL,
        [ChequeDate] DATETIME NULL,
        [BankName] NVARCHAR(50) NOT NULL,
        [BranchName] NVARCHAR(50) NOT NULL,
        [PaymentTerm] NVARCHAR(90) NOT NULL,
        CONSTRAINT [PK_tblPaymentV] PRIMARY KEY ([PaymentNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCommission]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCommission] (
        [CommNo] NVARCHAR(15) NOT NULL,
        [CustomerNo] NVARCHAR(25) NOT NULL,
        [ContactName] NVARCHAR(150) NOT NULL,
        [ContactMobile] NVARCHAR(80) NOT NULL,
        [Date_Out] DATETIME NOT NULL,
        [CommMonth] NVARCHAR(5) NOT NULL,
        [CondTypeNo] SMALLINT NOT NULL,
        [CommPercent] INT NOT NULL,
        [CommVat] FLOAT NOT NULL,
        [VatPrice] FLOAT NOT NULL,
        [CommPrice] FLOAT NOT NULL,
        [TotalPrice] FLOAT NOT NULL,
        [GrandTotalPrice] FLOAT NOT NULL,
        [BankName] NVARCHAR(100) NOT NULL,
        [BankAddress] NVARCHAR(20) NOT NULL,
        [AccountName] NVARCHAR(100) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblFormNo]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblFormNo] (
        [FormPONo] NCHAR(30) NULL,
        [FormPRNo] NCHAR(30) NULL,
        [FormRCNo] NCHAR(30) NULL,
        [FormQNNo] NCHAR(30) NULL,
        [FormDRNo] NCHAR(30) NULL,
        [FormNo1] NCHAR(30) NULL,
        [FormTINo] NCHAR(30) NULL,
        [FormDONo] NCHAR(30) NULL,
        [FormBILLNo] NCHAR(30) NULL,
        [FormCRNo] NCHAR(30) NULL,
        [FormNo2] NCHAR(30) NULL,
        [FormNo3] NCHAR(30) NULL,
        [FormNo4] NCHAR(30) NULL,
        [FormNo5] NCHAR(30) NULL,
        [FormNo6] NCHAR(30) NULL,
        [FormNo7] NCHAR(30) NULL,
        [FormNo8] NCHAR(30) NULL,
        [FormNo9] NCHAR(30) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblStatus]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblStatus] (
        [StatusNo] INT NOT NULL,
        [StatusName] NVARCHAR(30) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Contact]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Contact] (
        [ContactID] INT IDENTITY(1,1) NOT NULL,
        [IDnumber] NVARCHAR(15) NULL,
        [PrefixC] NVARCHAR(10) NULL,
        [FirstName] NVARCHAR(150) NULL,
        [LastName] NVARCHAR(120) NULL,
        [PositionC] NVARCHAR(200) NULL,
        [PhoneC] NVARCHAR(100) NULL,
        [FaxC] NVARCHAR(100) NULL,
        [PageC] NVARCHAR(100) NULL,
        [EmailC] NVARCHAR(100) NULL,
        [DefaultC] BIT NOT NULL,
        CONSTRAINT [PK_Contact] PRIMARY KEY ([ContactID])
    );
END
GO

IF OBJECT_ID(N'dbo.[Visuals]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Visuals] (
        [CalCode] NVARCHAR(15) NULL,
        [Item] INT NULL,
        [Scope] NVARCHAR(50) NULL,
        [Found] BIT NOT NULL,
        [Left] BIT NOT NULL,
        [Na] BIT NOT NULL,
        [Remarks] NTEXT NULL,
        [Group] NVARCHAR(1) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblExpData]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblExpData] (
        [ExpSubCode] NVARCHAR(3) NOT NULL,
        [ExpCode] NVARCHAR(6) NOT NULL,
        [ExpName] NVARCHAR(250) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCommissionList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCommissionList] (
        [CommNo] NVARCHAR(15) NULL,
        [ItemNo] INT NULL,
        [ListDate_Out] DATETIME NULL,
        [Description] NVARCHAR(150) NULL,
        [ListPrice] FLOAT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCalendar]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCalendar] (
        [WorkDate] DATETIME NOT NULL,
        [NameDate] NVARCHAR(50) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblExpMainData]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblExpMainData] (
        [ExpMainCode] NVARCHAR(2) NOT NULL,
        [ExpMainName] NVARCHAR(150) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCustomerRQ]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCustomerRQ] (
        [CRID] NVARCHAR(15) NOT NULL,
        [CRDate] DATETIME NULL,
        [CustomerID] NVARCHAR(15) NULL,
        [CRNo] NVARCHAR(15) NULL,
        [QuotationNo] NVARCHAR(80) NULL,
        CONSTRAINT [PK_tblCustomerRQ] PRIMARY KEY ([CRID])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblExpSubData]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblExpSubData] (
        [ExpMainCode] NVARCHAR(2) NOT NULL,
        [ExpSubCode] NVARCHAR(3) NOT NULL,
        [ExpSubName] NVARCHAR(150) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Technical]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Technical] (
        [TechId] NVARCHAR(5) NOT NULL,
        [TechName] NVARCHAR(100) NULL,
        [TechCode] NVARCHAR(50) NULL,
        [Position] NVARCHAR(80) NULL,
        [Department] NVARCHAR(120) NULL,
        [Phone] NVARCHAR(30) NULL,
        [Pager] NVARCHAR(30) NULL,
        [Picture] NVARCHAR(4) NULL,
        [Home] NVARCHAR(250) NULL,
        [City] NVARCHAR(80) NULL,
        [HomePhone] NVARCHAR(50) NULL,
        [ZipCode] NVARCHAR(12) NULL,
        [HireDate] NVARCHAR(50) NULL,
        [TerminatonDate] NVARCHAR(50) NULL,
        [Note] NTEXT NULL,
        [Assign] NTEXT NULL,
        [BirthDate] NVARCHAR(50) NULL,
        [Age] INT NULL,
        [TechStatus] BIT NOT NULL,
        [UserGroupName] NVARCHAR(150) NOT NULL,
        [Nickname] NVARCHAR(50) NOT NULL,
        [TitleNameThai] NVARCHAR(8) NOT NULL,
        [NameThai] NVARCHAR(100) NOT NULL,
        [SurnameThai] NVARCHAR(100) NOT NULL,
        [PLID] INT NOT NULL,
        [PersonID] NVARCHAR(17) NOT NULL,
        [EmailAddress] NVARCHAR(35) NOT NULL,
        CONSTRAINT [PK_Technical] PRIMARY KEY ([TechId])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblFunction]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblFunction] (
        [FunctionName] NVARCHAR(65) NOT NULL,
        CONSTRAINT [PK_tblFunction] PRIMARY KEY ([FunctionName])
    );
END
GO

IF OBJECT_ID(N'dbo.[JobDescription]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[JobDescription] (
        [TechId] NVARCHAR(5) NULL,
        [ItemJob] INT NULL,
        [Task] NVARCHAR(250) NULL,
        [Period] NVARCHAR(100) NULL,
        [Place] NVARCHAR(150) NULL,
        [Position] NVARCHAR(90) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCommmissionCond]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCommmissionCond] (
        [CondTypeNo] SMALLINT NOT NULL,
        [ConditionName] NVARCHAR(100) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblBankName]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblBankName] (
        [BankName] NVARCHAR(100) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCustomerRQItem]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCustomerRQItem] (
        [CRID] NVARCHAR(15) NULL,
        [ItemNo] INT NULL,
        [Description] NVARCHAR(150) NULL,
        [Manuf] NVARCHAR(150) NULL,
        [Model] NVARCHAR(100) NULL,
        [SerialNo] NVARCHAR(50) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblDeliveryItem]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblDeliveryItem] (
        [IssueNo] NVARCHAR(15) NULL,
        [ItemNo] INT NULL,
        [Description] NVARCHAR(150) NULL,
        [Manuf] NVARCHAR(150) NULL,
        [Model] NVARCHAR(100) NULL,
        [Unit] NVARCHAR(15) NULL,
        [Range] NVARCHAR(150) NULL,
        [Qty] INT NULL,
        [UDiscount] MONEY NULL,
        [UPrice] MONEY NULL,
        [TPrice] MONEY NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblTracking]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblTracking] (
        [OrderNo] NVARCHAR(15) NOT NULL,
        [Rec_By] NVARCHAR(5) NOT NULL,
        [Rec_Date] DATETIME NULL,
        [Rec_Note] NVARCHAR(150) NOT NULL,
        [Job_By] NVARCHAR(5) NOT NULL,
        [Job_Date] DATETIME NULL,
        [Job_Note] NVARCHAR(150) NOT NULL,
        [Lab_By] NVARCHAR(5) NOT NULL,
        [Lab_Date] DATETIME NULL,
        [Lab_Note] NVARCHAR(150) NOT NULL,
        [CS_By] NVARCHAR(5) NOT NULL,
        [CS_Date] DATETIME NULL,
        [CS_Note] NVARCHAR(150) NOT NULL,
        [TM_By] NVARCHAR(5) NOT NULL,
        [TM_Date] DATETIME NULL,
        [TM_Note] NVARCHAR(150) NOT NULL,
        [QA_By] NVARCHAR(5) NOT NULL,
        [QA_Date] DATETIME NULL,
        [QA_Note] NVARCHAR(150) NOT NULL,
        [INV_By] NVARCHAR(5) NOT NULL,
        [INV_Date] DATETIME NULL,
        [INV_Note] NVARCHAR(150) NOT NULL,
        [Rec_Finish] DATETIME NULL,
        [Job_Finish] DATETIME NULL,
        [Lab_Finish] DATETIME NULL,
        [CS_Finish] DATETIME NULL,
        [TM_Finish] DATETIME NULL,
        [QA_Finish] DATETIME NULL,
        [INV_Finish] DATETIME NULL,
        [StepP01] DATETIME NULL,
        [StepP02] DATETIME NULL,
        [StepP03] DATETIME NULL,
        [StepP04] DATETIME NULL,
        [StepP05] DATETIME NULL,
        [StepP06] DATETIME NULL,
        [StepP07] DATETIME NULL,
        [StepP08] DATETIME NULL,
        [StepP09] DATETIME NULL,
        [StepP10] DATETIME NULL,
        [StepP11] DATETIME NULL,
        [StepP12] DATETIME NULL,
        [StepP] INT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Product_R]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Product_R] (
        [TechId] NVARCHAR(5) NULL,
        [TechName] NVARCHAR(150) NULL,
        [CustomerName] NVARCHAR(120) NULL,
        [Description] NVARCHAR(150) NULL,
        [FinishDate] DATETIME NULL,
        [AssetNo] NVARCHAR(30) NULL,
        [Workorder] NVARCHAR(15) NULL,
        [JobNo] NVARCHAR(150) NULL,
        [CalH] FLOAT NULL,
        [RepairH] FLOAT NULL,
        [AdjH] FLOAT NULL,
        [MantH] FLOAT NULL,
        [RH] FLOAT NULL,
        [ProcH] FLOAT NULL,
        [IdleHrs] FLOAT NULL,
        [TranHrs] FLOAT NULL,
        [ProcHrs] FLOAT NULL,
        [NoteHrs] NTEXT NULL,
        [NoteTran] NTEXT NULL,
        [NoteProc] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPaymentVList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPaymentVList] (
        [PaymentNo] NVARCHAR(15) NOT NULL,
        [ItemNo] INT NULL,
        [PoNo] NVARCHAR(15) NOT NULL,
        [InvNo] NVARCHAR(15) NOT NULL,
        [InvDate] DATETIME NULL,
        [Description] NVARCHAR(150) NOT NULL,
        [Vat] FLOAT NOT NULL,
        [WHTax] FLOAT NOT NULL,
        [VatPrice] FLOAT NOT NULL,
        [WHPrice] FLOAT NOT NULL,
        [TotalPrice] FLOAT NOT NULL,
        [GrandTotalPrice] FLOAT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCreditNote]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCreditNote] (
        [CreditNoteNo] NVARCHAR(15) NOT NULL,
        [Date_out] DATETIME NOT NULL,
        [CustomerID] NVARCHAR(15) NOT NULL,
        [Subject] NVARCHAR(150) NOT NULL,
        [Vat] INT NULL,
        [VatPrice] FLOAT NULL,
        [DiffPrice] FLOAT NULL,
        [TotalPrice] FLOAT NOT NULL,
        [GrandTotalPrice] FLOAT NULL,
        [ApprovBy] NVARCHAR(5) NOT NULL,
        [RefDocNo] NVARCHAR(20) NOT NULL,
        [RefDate] DATETIME NULL,
        [TotalPriceRef] FLOAT NOT NULL,
        [Notes] NVARCHAR(250) NULL,
        [RefDocInv] BIT NOT NULL,
        [RefDocBill] BIT NOT NULL,
        [RefDocTaxInv] BIT NOT NULL,
        CONSTRAINT [PK_tblCreditNote] PRIMARY KEY ([CreditNoteNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblDelivery]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblDelivery] (
        [IssueNo] NVARCHAR(15) NOT NULL,
        [IssueDate] DATETIME NULL,
        [CustomerID] NVARCHAR(15) NULL,
        [Vat] INT NULL,
        [VatPrice] FLOAT NULL,
        [TotalPrice] FLOAT NULL,
        [GrandTotalPrice] FLOAT NULL,
        [Note] NTEXT NULL,
        [QuotationNo] NVARCHAR(80) NULL,
        [ReceiveNo] NVARCHAR(80) NULL,
        [RequestNo] NVARCHAR(80) NULL,
        [Payment] NVARCHAR(150) NULL,
        [DueDate] DATETIME NULL,
        [ReceiveName] NVARCHAR(100) NULL,
        [DeliveryName] NVARCHAR(100) NULL,
        [Subject] NVARCHAR(150) NULL,
        [DiscountPrice] FLOAT NULL,
        [ChkDiscountUnit] BIT NOT NULL,
        [PayMoney] BIT NOT NULL,
        [WHTax] FLOAT NOT NULL,
        [Comments] NVARCHAR(150) NOT NULL,
        [Billed] BIT NOT NULL,
        [BilledDate] DATETIME NULL,
        CONSTRAINT [PK_tblDelivery] PRIMARY KEY ([IssueNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblUnit]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblUnit] (
        [Unit] NVARCHAR(50) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblWHTax]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblWHTax] (
        [WHID] NVARCHAR(10) NOT NULL,
        [Date_wh] DATETIME NOT NULL,
        [DocumentNo] NVARCHAR(50) NULL,
        [RunningNo] NVARCHAR(50) NOT NULL,
        [ListName] NVARCHAR(250) NOT NULL,
        [TaxNo] NVARCHAR(25) NOT NULL,
        [Vat] FLOAT NOT NULL,
        [VatType] NVARCHAR(100) NOT NULL,
        [VatPrice] FLOAT NOT NULL,
        [TotalPrice] FLOAT NOT NULL,
        [GrandTotalPrice] FLOAT NOT NULL,
        [VatTypeNo] INT NULL,
        [PaymentType] INT NULL,
        [DocNo] NVARCHAR(7) NULL,
        CONSTRAINT [PK_tblWHTax] PRIMARY KEY ([WHID])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblTrace]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblTrace] (
        [Trace] NVARCHAR(50) NULL,
        [TraceDetail] NVARCHAR(150) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblEExpenses]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblEExpenses] (
        [EExpID] NVARCHAR(10) NOT NULL,
        [Date_exp] DATETIME NOT NULL,
        [DocumentNo] NVARCHAR(50) NULL,
        [Company] NVARCHAR(150) NULL,
        [ListName] NVARCHAR(250) NOT NULL,
        [Prices] FLOAT NOT NULL,
        [ByName] NVARCHAR(50) NULL,
        [Remarks] NVARCHAR(250) NULL,
        [ExpCode] NVARCHAR(15) NOT NULL,
        CONSTRAINT [PK_tblEExpenses] PRIMARY KEY ([EExpID])
    );
END
GO

IF OBJECT_ID(N'dbo.[ProductR]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[ProductR] (
        [TechId] NVARCHAR(5) NULL,
        [TechName] NVARCHAR(150) NULL,
        [CustomerName] NVARCHAR(120) NULL,
        [Description] NVARCHAR(150) NULL,
        [FinishDate] NVARCHAR(10) NULL,
        [AssetNo] NVARCHAR(30) NULL,
        [Workorder] NVARCHAR(15) NULL,
        [JobNo] NVARCHAR(150) NULL,
        [CalH] FLOAT NULL,
        [RepairH] FLOAT NULL,
        [AdjH] FLOAT NULL,
        [MantH] FLOAT NULL,
        [RH] FLOAT NULL,
        [ProcH] FLOAT NULL,
        [IdleHrs] FLOAT NULL,
        [TranHrs] FLOAT NULL,
        [ProcHrs] FLOAT NULL,
        [NoteHrs] NTEXT NULL,
        [NoteTran] NTEXT NULL,
        [NoteProc] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblTermPayment]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblTermPayment] (
        [TermPayment] NVARCHAR(120) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblIExpenses]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblIExpenses] (
        [IExpID] NVARCHAR(10) NOT NULL,
        [Date_exp] DATETIME NULL,
        [DocumentNo] NVARCHAR(50) NULL,
        [SuppID] NVARCHAR(10) NOT NULL,
        [ListName] NVARCHAR(250) NOT NULL,
        [Vat] INT NOT NULL,
        [VatPrice] FLOAT NOT NULL,
        [TotalPrice] FLOAT NOT NULL,
        [GrandTotalPrice] FLOAT NOT NULL,
        [Remarks] NVARCHAR(250) NULL,
        [ExpCode] NVARCHAR(15) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblSupplier]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblSupplier] (
        [SuppID] NVARCHAR(15) NULL,
        [SuppName] NVARCHAR(120) NULL,
        [Address] NVARCHAR(255) NULL,
        [PhoneNo] NVARCHAR(35) NULL,
        [FaxNo] NVARCHAR(35) NULL,
        [ContactName] NVARCHAR(150) NULL,
        [TaxNo] NVARCHAR(25) NULL,
        [EmailNo] NVARCHAR(150) NULL,
        [Cash] BIT NOT NULL,
        [Cheque] BIT NOT NULL,
        [Transfers] BIT NOT NULL,
        [Others] BIT NOT NULL,
        [OtherName] NVARCHAR(50) NOT NULL,
        [ChequeNo] NVARCHAR(50) NOT NULL,
        [BankName] NVARCHAR(50) NOT NULL,
        [BranchName] NVARCHAR(50) NOT NULL,
        [PaymentTerm] NVARCHAR(90) NOT NULL,
        [ChequeDate] DATETIME NULL,
        [ChequeCost] FLOAT NOT NULL,
        [EmailNoAcc] NVARCHAR(150) NULL,
        [SuppBranch] NVARCHAR(100) NOT NULL,
        [ContactAcc] NVARCHAR(150) NOT NULL,
        [AttachFile] NVARCHAR(150) NOT NULL,
        [Remarks] NVARCHAR(250) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCreditNoteItem]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCreditNoteItem] (
        [CreditNoteNo] NVARCHAR(15) NOT NULL,
        [ItemNo] INT NOT NULL,
        [Description] NVARCHAR(150) NOT NULL,
        [Manuf] NVARCHAR(150) NULL,
        [Model] NVARCHAR(100) NULL,
        [Unit] NVARCHAR(15) NULL,
        [Range] NVARCHAR(150) NULL,
        [Qty] INT NULL,
        [PrevUprice] MONEY NOT NULL,
        [UPrice] MONEY NOT NULL,
        [TPrice] MONEY NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblStandTrace]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblStandTrace] (
        [StandID] NVARCHAR(15) NULL,
        [Trace] NVARCHAR(50) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[AccessDescription]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[AccessDescription] (
        [Description] NVARCHAR(150) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblLabName]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblLabName] (
        [LabNo] NVARCHAR(2) NOT NULL,
        [LabName] NVARCHAR(80) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCurrency]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCurrency] (
        [CurrencyID] NVARCHAR(1) NULL,
        [Currency] NVARCHAR(10) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblResultType]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblResultType] (
        [ResultTypeID] INT IDENTITY(1,1) NOT NULL,
        [ResultType] NVARCHAR(50) NULL,
        CONSTRAINT [PK_tblResultType] PRIMARY KEY ([ResultTypeID])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCompany]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCompany] (
        [CompanyName] NVARCHAR(120) NULL,
        [Address] NVARCHAR(255) NULL,
        [Province] NVARCHAR(80) NULL,
        [PostalNo] NVARCHAR(10) NULL,
        [PhoneNo] NVARCHAR(35) NULL,
        [FaxNo] NVARCHAR(35) NULL,
        [ContactName] NVARCHAR(80) NULL,
        [QuoContact] NVARCHAR(250) NULL,
        [WebsiteName] NVARCHAR(250) NULL,
        [EmailName] NVARCHAR(250) NULL,
        [ProcedureUse] NTEXT NULL,
        [ProcedureNotAcc] NTEXT NULL,
        [ProcedureManual] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblControlNo]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblControlNo] (
        [ControlID] NVARCHAR(10) NOT NULL,
        [ControlNo] NVARCHAR(30) NOT NULL,
        [Date_exp] DATETIME NOT NULL,
        [Description] NVARCHAR(150) NOT NULL,
        [MasterForm1] NVARCHAR(200) NOT NULL,
        [MasterForm2] NVARCHAR(200) NOT NULL,
        [MasterForm3] NVARCHAR(200) NOT NULL,
        [MasterForm4] NVARCHAR(200) NOT NULL,
        CONSTRAINT [PK_tblControlNo] PRIMARY KEY ([ControlID])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblResult]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblResult] (
        [ResultID] INT IDENTITY(1,1) NOT NULL,
        [ResultName] NVARCHAR(80) NULL,
        [ResultTypeID] INT NULL,
        CONSTRAINT [PK_tblResult] PRIMARY KEY ([ResultID])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCheque]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCheque] (
        [CQNo] NVARCHAR(10) NOT NULL,
        [Date_out] DATETIME NULL,
        [SuppID] NVARCHAR(15) NULL,
        [TotalPrice] FLOAT NULL,
        [ChequeNo] NVARCHAR(10) NULL,
        CONSTRAINT [PK_tblCheque] PRIMARY KEY ([CQNo])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblBillList]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblBillList] (
        [BillNo] NVARCHAR(15) NULL,
        [ItemNo] INT NULL,
        [InvoiceNo] NVARCHAR(15) NULL,
        [InvoiceDate] DATETIME NULL,
        [Description] NVARCHAR(150) NULL,
        [TotalPrice] FLOAT NULL,
        [GrandTotalPrice] FLOAT NULL,
        [WHTax] FLOAT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPayable]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPayable] (
        [PayableID] NVARCHAR(15) NOT NULL,
        [Date_out] DATETIME NOT NULL,
        [TaxInvNo] NVARCHAR(30) NOT NULL,
        [SuppID] NVARCHAR(15) NOT NULL,
        [ExpCode] NVARCHAR(15) NOT NULL,
        [Vat] INT NOT NULL,
        [VatPrice] FLOAT NOT NULL,
        [TotalPrice] FLOAT NOT NULL,
        [DiscountPrice] FLOAT NOT NULL,
        [GrandTotalPrice] FLOAT NOT NULL,
        [DueDate] DATETIME NOT NULL,
        [Remarks] NVARCHAR(250) NULL,
        [PoNo] NVARCHAR(15) NOT NULL,
        [WHTax] FLOAT NOT NULL,
        [WHPrice] FLOAT NOT NULL,
        CONSTRAINT [PK_tblPayable] PRIMARY KEY ([PayableID])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblCustomerReq]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblCustomerReq] (
        [CustomerID] NVARCHAR(15) NOT NULL,
        [Cert00] BIT NOT NULL,
        [Cert01] BIT NOT NULL,
        [Cert02] BIT NOT NULL,
        [Cert03] BIT NOT NULL,
        [Cert04] BIT NOT NULL,
        [Cert05] BIT NOT NULL,
        [Cert06] BIT NOT NULL,
        [Cert07] BIT NOT NULL,
        [Data00] BIT NOT NULL,
        [Data01] BIT NOT NULL,
        [Data02] BIT NOT NULL,
        [Data03] BIT NOT NULL,
        [Data04] BIT NOT NULL,
        [Data05] BIT NOT NULL,
        [Data06] BIT NOT NULL,
        [Data07] BIT NOT NULL,
        [Data08] BIT NOT NULL,
        [Data09] BIT NOT NULL,
        [Data10] BIT NOT NULL,
        [Data11] BIT NOT NULL,
        [Onsite00] BIT NOT NULL,
        [Onsite01] BIT NOT NULL,
        [Onsite02] BIT NOT NULL,
        [Onsite03] BIT NOT NULL,
        [Onsite04] BIT NOT NULL,
        [Onsite05] BIT NOT NULL,
        [Sticker00] BIT NOT NULL,
        [Sticker01] BIT NOT NULL,
        [Sticker02] BIT NOT NULL,
        [Sticker03] BIT NOT NULL,
        [Sticker04] BIT NOT NULL,
        [Sticker05] BIT NOT NULL,
        [Sticker06] BIT NOT NULL,
        [Sticker07] BIT NOT NULL,
        [Special00] BIT NOT NULL,
        [Special01] BIT NOT NULL,
        [Special02] BIT NOT NULL,
        [Special03] BIT NOT NULL,
        [Special04] BIT NOT NULL,
        [Special05] BIT NOT NULL,
        [Special06] BIT NOT NULL,
        [Special07] BIT NOT NULL,
        [Special08] BIT NOT NULL,
        [Special09] BIT NOT NULL,
        [Special10] BIT NOT NULL,
        [Special11] BIT NOT NULL,
        [Package00] BIT NOT NULL,
        [Package01] BIT NOT NULL,
        [Package02] BIT NOT NULL,
        [Package03] BIT NOT NULL,
        [Package04] BIT NOT NULL,
        [Package05] BIT NOT NULL,
        [CertReq] NVARCHAR(1500) NOT NULL,
        [DataReq] NVARCHAR(1500) NOT NULL,
        [OnsiteReq] NVARCHAR(1500) NOT NULL,
        [StickerReq] NVARCHAR(1500) NOT NULL,
        [SpecialReq] NVARCHAR(1500) NOT NULL,
        [PackageReq] NVARCHAR(1500) NOT NULL,
        [AttachFile1] NVARCHAR(500) NOT NULL,
        [AttachFile2] NVARCHAR(500) NOT NULL,
        [MemberID] NVARCHAR(20) NOT NULL,
        [MemReg] BIT NOT NULL,
        CONSTRAINT [PK_tblCustomerReq] PRIMARY KEY ([CustomerID])
    );
END
GO

IF OBJECT_ID(N'dbo.[tblAddressReport]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblAddressReport] (
        [CompanyNameThai] NCHAR(150) NULL,
        [CompanyNameEng] NCHAR(150) NULL,
        [Address1Thai] NCHAR(100) NULL,
        [Address2Thai] NCHAR(100) NULL,
        [Address3Thai] NCHAR(100) NULL,
        [Address1Eng] NCHAR(100) NULL,
        [Address2Eng] NCHAR(100) NULL,
        [Address3Eng] NCHAR(100) NULL,
        [TaxNo] NCHAR(100) NULL,
        [Address1Thai1] NCHAR(100) NULL,
        [Address2Thai1] NCHAR(100) NULL,
        [Address3Thai1] NCHAR(100) NULL,
        [Address1Eng1] NCHAR(100) NULL,
        [Address2Eng1] NCHAR(100) NULL,
        [Address3Eng1] NCHAR(100) NULL,
        [ChkDefault] INT NULL,
        [ChkDefault1] INT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[TblRecall]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[TblRecall] (
        [CalCode] NVARCHAR(15) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblBonus]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblBonus] (
        [NetIncome] NVARCHAR(150) NOT NULL,
        [BonusCondition] NVARCHAR(150) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblBill]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblBill] (
        [BillNo] NVARCHAR(15) NULL,
        [Date_out] DATETIME NULL,
        [CustomerID] NVARCHAR(15) NULL,
        [DiscountPrice] FLOAT NULL,
        [Vat] INT NULL,
        [VatPrice] FLOAT NULL,
        [TotalPrice] FLOAT NULL,
        [GrandTotalPrice] FLOAT NULL,
        [Note] NTEXT NULL,
        [RefNo] NVARCHAR(150) NULL,
        [BillPerson] NVARCHAR(100) NULL,
        [Date_bill] DATETIME NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[ScheduleStandard]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[ScheduleStandard] (
        [Item] NVARCHAR(5) NULL,
        [CalCode] NVARCHAR(15) NULL,
        [ExpectedDate] NVARCHAR(10) NULL,
        [Corrospond] NVARCHAR(100) NULL,
        [Replacement] NVARCHAR(100) NULL,
        [Ship] NVARCHAR(100) NULL,
        [Authority] NVARCHAR(100) NULL,
        [ContactName] NVARCHAR(60) NULL,
        [ContactPhone] NVARCHAR(50) NULL,
        [Purchase] NVARCHAR(20) NULL,
        [National] NVARCHAR(10) NULL,
        [Note] NTEXT NULL,
        [NoteAuthority] NTEXT NULL,
        [NoteCorrospond] NTEXT NULL,
        [NoteReplacement] NTEXT NULL,
        [NoteExpectedDate] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblHistoryEnv]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblHistoryEnv] (
        [LabID] INT NOT NULL,
        [LabName] NVARCHAR(4) NOT NULL,
        [TempA] INT NOT NULL,
        [TempB] INT NOT NULL,
        [RhA] INT NOT NULL,
        [RhB] INT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Description_BK]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Description_BK] (
        [DescriptionId] NVARCHAR(9) NOT NULL,
        [DescriptionName] NVARCHAR(255) NULL,
        [Price] MONEY NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPL]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPL] (
        [PLID] INT NOT NULL,
        [PLName] NVARCHAR(150) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[SubDescription]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[SubDescription] (
        [DescriptionId] NVARCHAR(8) NULL,
        [Manufecturer] NVARCHAR(80) NULL,
        [Model] NVARCHAR(70) NULL,
        [Range] NVARCHAR(120) NULL,
        [TestPoint] NVARCHAR(120) NULL,
        [Prices] MONEY NULL,
        [PartGroup] NCHAR(10) NULL,
        [Cert_Normal] BIT NULL,
        [Cert_17025] BIT NULL,
        [Accreditation_LAB] BIT NULL,
        [Accreditation_ONSITE] BIT NULL,
        [Sub_Contractor] BIT NULL,
        [ProcedureNo] NVARCHAR(150) NULL,
        [Cert_17025_ANAB] BIT NOT NULL,
        [LabNo] NVARCHAR(2) NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Procedure]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Procedure] (
        [ProcedureID] NVARCHAR(15) NULL,
        [ProcedureName] NVARCHAR(200) NULL,
        [Revission] NVARCHAR(80) NULL,
        [RevissionDate] NVARCHAR(10) NULL,
        [Approved] NVARCHAR(80) NULL,
        [Design] NVARCHAR(80) NULL,
        [DocumentPath] NVARCHAR(150) NULL,
        [ProcedureType] BIT NOT NULL,
        [Note] NTEXT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblSalary]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblSalary] (
        [SalaryID] NVARCHAR(15) NOT NULL,
        [TechId] NVARCHAR(5) NOT NULL,
        [SalaryDate] DATETIME NOT NULL,
        [SalaryMonth] NVARCHAR(5) NULL,
        [PositionType] SMALLINT NOT NULL,
        [Salary] FLOAT NOT NULL,
        [Compensation] FLOAT NOT NULL,
        [Gasoline] FLOAT NOT NULL,
        [Breakage] FLOAT NOT NULL,
        [Mobile] FLOAT NOT NULL,
        [Overtime] FLOAT NOT NULL,
        [Allowance] FLOAT NOT NULL,
        [Specials] FLOAT NOT NULL,
        [Bonus] FLOAT NOT NULL,
        [TotalSale] FLOAT NOT NULL,
        [DeductComm] FLOAT NOT NULL,
        [Deduct] FLOAT NOT NULL,
        [Commission] FLOAT NOT NULL,
        [HourWork] FLOAT NULL,
        [SocialVat] FLOAT NOT NULL,
        [TotalReceive] FLOAT NOT NULL,
        [WithHolding] FLOAT NOT NULL,
        [Social] FLOAT NOT NULL,
        [TotalExpense] FLOAT NOT NULL,
        [GrandTotal] FLOAT NOT NULL,
        [Others] FLOAT NOT NULL,
        [DeductPercent] INT NOT NULL,
        [DeductSalary] FLOAT NOT NULL,
        [FullMonth] BIT NOT NULL,
        [DateOfWork] FLOAT NOT NULL,
        [SalaryForOT] FLOAT NOT NULL,
        [SalaryFix] FLOAT NOT NULL,
        [StudentLoan] FLOAT NOT NULL,
        [EmployeeFund] FLOAT NOT NULL,
        [EmployeeFundPercent] FLOAT NOT NULL,
        [SalaryBase] FLOAT NOT NULL,
        [WH3Perc] BIT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[SubDescription_BK]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[SubDescription_BK] (
        [DescriptionId] NVARCHAR(8) NULL,
        [Manufecturer] NVARCHAR(80) NULL,
        [Model] NVARCHAR(70) NULL,
        [Range] NVARCHAR(120) NULL,
        [TestPoint] NVARCHAR(120) NULL,
        [Prices] MONEY NULL,
        [PartGroup] NCHAR(10) NULL,
        [Cert_Normal] BIT NULL,
        [Cert_17025] BIT NULL,
        [Accreditation_LAB] BIT NULL,
        [Accreditation_ONSITE] BIT NULL,
        [Sub_Contractor] BIT NULL,
        [ProcedureNo] NVARCHAR(150) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblPR]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblPR] (
        [PRNo] NVARCHAR(10) NULL,
        [Date_out] DATETIME NULL,
        [SuppID] NVARCHAR(15) NULL,
        [Vat] INT NULL,
        [VatPrice] FLOAT NULL,
        [TotalPrice] FLOAT NULL,
        [GrandTotalPrice] FLOAT NULL,
        [Discount] FLOAT NULL,
        [FixAsset] BIT NOT NULL,
        [Expense] BIT NOT NULL,
        [Others] BIT NOT NULL,
        [OtherName] NVARCHAR(50) NULL,
        [QuantationNo] NVARCHAR(30) NULL,
        [PRTo] NVARCHAR(150) NULL,
        [PRFrom] NVARCHAR(150) NULL,
        [Department] NVARCHAR(150) NULL,
        [ExpCode] NVARCHAR(15) NOT NULL,
        [RequestID] NVARCHAR(5) NOT NULL,
        [AttachFileName] NVARCHAR(200) NOT NULL,
        [PONo] NVARCHAR(10) NOT NULL,
        [DepartmentAppvID] NVARCHAR(5) NOT NULL,
        [Date_TMAppv] DATETIME NULL,
        [DepartmentAppv] BIT NULL,
        [LabAppvID] NVARCHAR(5) NOT NULL,
        [Date_LMAppv] DATETIME NULL,
        [LabAppv] BIT NULL,
        [PurchaseAppvID] NVARCHAR(5) NOT NULL,
        [Date_PMAppv] DATETIME NULL,
        [PurchaseAppv] BIT NULL,
        [MDGM_Sign] BIT NULL,
        [MDAppvID] NVARCHAR(5) NOT NULL,
        [Date_MDAppv] DATETIME NULL,
        [MDAppv] BIT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[Mantan]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[Mantan] (
        [Item] NVARCHAR(3) NULL,
        [CalCode] NVARCHAR(15) NULL,
        [MDate] NVARCHAR(10) NULL,
        [NMDate] NVARCHAR(10) NULL,
        [Scope] NTEXT NULL,
        [Result] NTEXT NULL,
        [Remark] NTEXT NULL,
        [SuppID] NVARCHAR(15) NOT NULL,
        [MCost] FLOAT NOT NULL
    );
END
GO

IF OBJECT_ID(N'dbo.[tblUserGroup]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[tblUserGroup] (
        [UserGroupName] NVARCHAR(150) NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_Quotation_QuotationNo' AND object_id = OBJECT_ID(N'dbo.Quotation'))
    ALTER TABLE dbo.[Quotation] ADD CONSTRAINT [UQ_Quotation_QuotationNo] UNIQUE ([QuotationNo]);
GO

IF OBJECT_ID(N'dbo.FK_QuotationItem_Quotation_QuotationNo', N'F') IS NULL
    ALTER TABLE dbo.[QuotationItem] ADD CONSTRAINT [FK_QuotationItem_Quotation_QuotationNo]
        FOREIGN KEY ([QuotationNo]) REFERENCES dbo.[Quotation] ([QuotationNo]);
GO

IF OBJECT_ID(N'dbo.FK_QuotationRemark_Quotation_QuotationNo', N'F') IS NULL
    ALTER TABLE dbo.[QuotationRemark] ADD CONSTRAINT [FK_QuotationRemark_Quotation_QuotationNo]
        FOREIGN KEY ([QuotationNo]) REFERENCES dbo.[Quotation] ([QuotationNo]);
GO

