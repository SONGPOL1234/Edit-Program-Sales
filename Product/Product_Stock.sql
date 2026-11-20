/* =====================================================================
   PCal - Product & Stock (ธุรกิจซื้อมา-ขายไป)
   SQL Server 2016+  · ออกแบบให้ต่อกับ Quotation (Subject = Product) และ Customer Master
   ตาราง:  Pd_Category, Pd_Supplier, Pd_Product, Pd_StockMove, Pd_PurchaseOrder/Line,
           Pd_SaleLine (ต้นทุน ณ วันขาย), Pd_GpApproval, Pd_ReorderFollow
   วิว:    v_Pd_Stock, v_Pd_ReorderSuggest, v_Pd_CustomerReorderDue, v_Pd_LowGP
   Proc:   sp_Pd_Receive, sp_Pd_Issue, sp_Pd_Adjust, sp_Pd_CreatePOFromSuggest,
           sp_Pd_ReceivePO, sp_Pd_CheckGP
   หมายเหตุ: ต้นทุนใช้แบบถัวเฉลี่ยเคลื่อนที่ (Moving Average) ปรับทุกครั้งที่รับของ
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ---------- 1. Master ---------- */
IF OBJECT_ID('dbo.Pd_Category') IS NULL
CREATE TABLE dbo.Pd_Category(
  CategoryId    TINYINT       NOT NULL PRIMARY KEY,
  CategoryName  NVARCHAR(100) NOT NULL,
  MinGPPct      DECIMAL(5,2)  NOT NULL DEFAULT 20   -- ต่ำกว่านี้ต้องขออนุมัติ
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Pd_Category)
INSERT dbo.Pd_Category VALUES
 (0,N'วัสดุสิ้นเปลือง',25),(1,N'เครื่องมือวัด',15),(2,N'มาตรฐานอ้างอิง',12),(3,N'อะไหล่/อุปกรณ์เสริม',20);
GO

IF OBJECT_ID('dbo.Pd_Supplier') IS NULL
CREATE TABLE dbo.Pd_Supplier(
  SupplierCode  VARCHAR(10)   NOT NULL PRIMARY KEY,
  SupplierName  NVARCHAR(200) NOT NULL,
  TaxId         VARCHAR(20)   NULL,
  ContactName   NVARCHAR(100) NULL,
  Tel           VARCHAR(50)   NULL,
  Email         VARCHAR(150)  NULL,
  LeadDays      SMALLINT      NOT NULL DEFAULT 14,
  PaymentTerm   NVARCHAR(50)  NULL,
  Active        BIT           NOT NULL DEFAULT 1
);
GO

IF OBJECT_ID('dbo.Pd_Product') IS NULL
CREATE TABLE dbo.Pd_Product(
  ProductId     INT IDENTITY  PRIMARY KEY,
  Sku           VARCHAR(20)   NOT NULL UNIQUE,
  ProductName   NVARCHAR(200) NOT NULL,
  Brand         NVARCHAR(100) NULL,
  Model         NVARCHAR(100) NULL,
  CategoryId    TINYINT       NOT NULL REFERENCES dbo.Pd_Category(CategoryId),
  Unit          NVARCHAR(20)  NOT NULL DEFAULT N'ชิ้น',
  SupplierCode  VARCHAR(10)   NULL REFERENCES dbo.Pd_Supplier(SupplierCode),
  ListPrice     DECIMAL(14,2) NOT NULL DEFAULT 0,     -- ราคาขายมาตรฐาน
  AvgCost       DECIMAL(14,4) NOT NULL DEFAULT 0,     -- ต้นทุนเฉลี่ยเคลื่อนที่ (ระบบปรับเอง)
  OnHand        DECIMAL(12,2) NOT NULL DEFAULT 0,     -- ระบบปรับจาก Pd_StockMove
  Reserved      DECIMAL(12,2) NOT NULL DEFAULT 0,     -- จองจาก PO ลูกค้าที่ยังไม่ส่ง
  ReorderPoint  DECIMAL(12,2) NOT NULL DEFAULT 0,
  UsageCycleDays SMALLINT     NOT NULL DEFAULT 0,     -- รอบใช้งานวัสดุสิ้นเปลือง (0 = ไม่เตือน)
  Active        BIT           NOT NULL DEFAULT 1,
  CreatedAt     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
  UpdatedAt     DATETIME2(0)  NULL,
  Available AS (OnHand - Reserved) PERSISTED
);
GO

/* ---------- 2. Stock movement (สมุดคุมสต็อก) ---------- */
IF OBJECT_ID('dbo.Pd_StockMove') IS NULL
CREATE TABLE dbo.Pd_StockMove(
  MoveId        BIGINT IDENTITY PRIMARY KEY,
  MoveDate      DATE          NOT NULL,
  MoveType      CHAR(3)       NOT NULL CHECK (MoveType IN ('GR','IS','ADJ')),
  ProductId     INT           NOT NULL REFERENCES dbo.Pd_Product(ProductId),
  Qty           DECIMAL(12,2) NOT NULL,              -- + เข้า / − ออก
  UnitCost      DECIMAL(14,4) NULL,                  -- GR = ทุนรับเข้า, IS/ADJ = ทุนเฉลี่ย ณ ขณะนั้น
  DocNo         VARCHAR(30)   NULL,                  -- เลข Invoice / GR / ADJ
  CustomerId    VARCHAR(20)   NULL,                  -- อ้างอิง Customer Master (ตอนขาย)
  VendorPONo    VARCHAR(20)   NULL,
  Note          NVARCHAR(300) NULL,
  CreatedBy     NVARCHAR(50)  NULL,
  CreatedAt     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT CK_Pd_Move_Sign CHECK ((MoveType='GR' AND Qty>0) OR (MoveType='IS' AND Qty<0) OR MoveType='ADJ'),
  CONSTRAINT CK_Pd_Move_AdjNote CHECK (MoveType<>'ADJ' OR Note IS NOT NULL)
);
CREATE INDEX IX_Pd_Move_Prod ON dbo.Pd_StockMove(ProductId, MoveDate DESC);
GO

/* ---------- 3. Vendor PO ---------- */
IF OBJECT_ID('dbo.Pd_PurchaseOrder') IS NULL
CREATE TABLE dbo.Pd_PurchaseOrder(
  VendorPONo    VARCHAR(20)   NOT NULL PRIMARY KEY,   -- PO-Vyy####
  SupplierCode  VARCHAR(10)   NOT NULL REFERENCES dbo.Pd_Supplier(SupplierCode),
  PODate        DATE          NOT NULL,
  ETA           DATE          NULL,
  Status        VARCHAR(10)   NOT NULL DEFAULT 'DRAFT'
                CHECK (Status IN ('DRAFT','SENT','PARTIAL','RECEIVED','CANCEL')),
  Remark        NVARCHAR(300) NULL,
  CreatedBy     NVARCHAR(50)  NULL,
  CreatedAt     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
IF OBJECT_ID('dbo.Pd_PurchaseOrderLine') IS NULL
CREATE TABLE dbo.Pd_PurchaseOrderLine(
  VendorPONo    VARCHAR(20)   NOT NULL REFERENCES dbo.Pd_PurchaseOrder(VendorPONo),
  LineNo        SMALLINT      NOT NULL,
  ProductId     INT           NOT NULL REFERENCES dbo.Pd_Product(ProductId),
  Qty           DECIMAL(12,2) NOT NULL CHECK (Qty>0),
  UnitCost      DECIMAL(14,4) NOT NULL,
  QtyReceived   DECIMAL(12,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (VendorPONo, LineNo)
);
GO

/* ---------- 4. บรรทัดขาย (เก็บต้นทุน ณ วันขาย เพื่อคิด GP จริง) ---------- */
IF OBJECT_ID('dbo.Pd_SaleLine') IS NULL
CREATE TABLE dbo.Pd_SaleLine(
  SaleLineId    BIGINT IDENTITY PRIMARY KEY,
  InvoiceNo     VARCHAR(30)   NOT NULL,
  InvoiceDate   DATE          NOT NULL,
  QuotationNo   VARCHAR(20)   NULL,                  -- อ้าง Quotation (Subject = Product)
  CustomerId    VARCHAR(20)   NOT NULL,
  SaleName      NVARCHAR(100) NULL,
  ProductId     INT           NOT NULL REFERENCES dbo.Pd_Product(ProductId),
  Qty           DECIMAL(12,2) NOT NULL,
  UnitPrice     DECIMAL(14,2) NOT NULL,              -- ราคาสุทธิหลังส่วนลด
  UnitCostAtSale DECIMAL(14,4) NOT NULL,
  GPPct AS (CASE WHEN UnitPrice>0 THEN CAST((UnitPrice-UnitCostAtSale)/UnitPrice*100 AS DECIMAL(7,2)) END) PERSISTED
);
CREATE INDEX IX_Pd_Sale_CustProd ON dbo.Pd_SaleLine(CustomerId, ProductId, InvoiceDate DESC);
GO

IF OBJECT_ID('dbo.Pd_GpApproval') IS NULL
CREATE TABLE dbo.Pd_GpApproval(
  ApprovalId    INT IDENTITY PRIMARY KEY,
  QuotationNo   VARCHAR(20)   NULL,
  InvoiceNo     VARCHAR(30)   NULL,
  ProductId     INT           NOT NULL,
  ProposedPrice DECIMAL(14,2) NOT NULL,
  GPPct         DECIMAL(7,2)  NOT NULL,
  MinGPPct      DECIMAL(5,2)  NOT NULL,
  Status        CHAR(1)       NOT NULL DEFAULT 'P' CHECK (Status IN ('P','A','R')),
  Reason        NVARCHAR(300) NULL,
  RequestedBy   NVARCHAR(50)  NULL,
  ApprovedBy    NVARCHAR(50)  NULL,
  ApprovedAt    DATETIME2(0)  NULL
);
GO

IF OBJECT_ID('dbo.Pd_ReorderFollow') IS NULL
CREATE TABLE dbo.Pd_ReorderFollow(
  CustomerId    VARCHAR(20)   NOT NULL,
  ProductId     INT           NOT NULL,
  LastInvoiceDate DATE        NOT NULL,              -- รอบที่ติดตาม (ซื้อรอบใหม่ = แถวใหม่)
  FollowStatus  CHAR(1)       NOT NULL CHECK (FollowStatus IN ('C','O','X')), -- ติดต่อแล้ว/ได้ออเดอร์/ไม่สั่งแล้ว
  Note          NVARCHAR(300) NULL,
  UpdatedBy     NVARCHAR(50)  NULL,
  UpdatedAt     DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
  PRIMARY KEY (CustomerId, ProductId, LastInvoiceDate)
);
GO

/* ---------- 5. Views ---------- */
CREATE OR ALTER VIEW dbo.v_Pd_Stock AS
WITH s12 AS (
  SELECT ProductId, SUM(Qty) Qty12, SUM(Qty*UnitPrice) Amt12, MAX(InvoiceDate) LastSale
  FROM dbo.Pd_SaleLine WHERE InvoiceDate > DATEADD(DAY,-365,CAST(GETDATE() AS DATE)) GROUP BY ProductId),
oo AS (
  SELECT l.ProductId, SUM(l.Qty-l.QtyReceived) OnOrder
  FROM dbo.Pd_PurchaseOrderLine l JOIN dbo.Pd_PurchaseOrder h ON h.VendorPONo=l.VendorPONo
  WHERE h.Status IN ('DRAFT','SENT','PARTIAL') GROUP BY l.ProductId)
SELECT p.ProductId,p.Sku,p.ProductName,p.Brand,p.Model,p.CategoryId,c.CategoryName,p.Unit,p.SupplierCode,
       p.OnHand,p.Reserved,p.Available,ISNULL(oo.OnOrder,0) OnOrder,p.ReorderPoint,
       p.AvgCost,p.ListPrice,
       CAST(CASE WHEN p.ListPrice>0 THEN (p.ListPrice-p.AvgCost)/p.ListPrice*100 END AS DECIMAL(7,2)) ListGPPct,
       c.MinGPPct, ISNULL(s12.Qty12,0) Qty12, ISNULL(s12.Amt12,0) Amt12, s12.LastSale,
       CAST(CASE WHEN ISNULL(s12.Qty12,0)>0 THEN p.Available/(s12.Qty12/365.0) END AS DECIMAL(9,1)) DaysCover,
       p.OnHand*p.AvgCost StockValue,
       CASE WHEN p.OnHand<=0 THEN 'OUT'
            WHEN p.Available+ISNULL(oo.OnOrder,0)<p.ReorderPoint THEN 'LOW'
            WHEN p.Available<p.ReorderPoint THEN 'INCOMING' ELSE 'OK' END StockStatus
FROM dbo.Pd_Product p
JOIN dbo.Pd_Category c ON c.CategoryId=p.CategoryId
LEFT JOIN s12 ON s12.ProductId=p.ProductId
LEFT JOIN oo  ON oo.ProductId=p.ProductId
WHERE p.Active=1;
GO

/* แนะนำสั่งซื้อ: ขายช่วงรอของ + 30 วัน − (พร้อมขาย+กำลังมา) ไม่น้อยกว่า ROP */
CREATE OR ALTER VIEW dbo.v_Pd_ReorderSuggest AS
SELECT s.ProductId,s.Sku,s.ProductName,s.SupplierCode,sp.SupplierName,sp.LeadDays,
       s.Available,s.OnOrder,s.ReorderPoint,s.Qty12,s.AvgCost,
       CAST(CASE WHEN q.Need>s.ReorderPoint THEN q.Need ELSE s.ReorderPoint END AS DECIMAL(12,0)) SuggestQty
FROM dbo.v_Pd_Stock s
JOIN dbo.Pd_Supplier sp ON sp.SupplierCode=s.SupplierCode
CROSS APPLY (SELECT CEILING(s.Qty12/365.0*(sp.LeadDays+30)) - (s.Available+s.OnOrder) AS Need) q
WHERE s.Available+s.OnOrder < s.ReorderPoint;
GO

/* ลูกค้าครบรอบสั่งซ้ำ: ซื้อล่าสุด + รอบใช้งาน, ตัดคนที่ปิดการติดตามรอบนั้นแล้ว */
CREATE OR ALTER VIEW dbo.v_Pd_CustomerReorderDue AS
WITH last AS (
  SELECT sl.*, ROW_NUMBER() OVER (PARTITION BY sl.CustomerId, sl.ProductId ORDER BY sl.InvoiceDate DESC, sl.SaleLineId DESC) rn
  FROM dbo.Pd_SaleLine sl)
SELECT l.CustomerId,l.ProductId,p.Sku,p.ProductName,p.UsageCycleDays,l.InvoiceNo,l.InvoiceDate LastBuy,l.Qty,l.UnitPrice,l.SaleName,
       DATEADD(DAY,p.UsageCycleDays,l.InvoiceDate) DueDate,
       DATEDIFF(DAY,CAST(GETDATE() AS DATE),DATEADD(DAY,p.UsageCycleDays,l.InvoiceDate)) DaysToDue,
       f.FollowStatus,f.Note
FROM last l
JOIN dbo.Pd_Product p ON p.ProductId=l.ProductId AND p.UsageCycleDays>0 AND p.Active=1
LEFT JOIN dbo.Pd_ReorderFollow f ON f.CustomerId=l.CustomerId AND f.ProductId=l.ProductId AND f.LastInvoiceDate=l.InvoiceDate
WHERE l.rn=1;
GO

CREATE OR ALTER VIEW dbo.v_Pd_LowGP AS
SELECT sl.SaleLineId,sl.InvoiceNo,sl.InvoiceDate,sl.CustomerId,sl.SaleName,p.Sku,p.ProductName,sl.Qty,sl.UnitPrice,sl.UnitCostAtSale,sl.GPPct,c.MinGPPct,
       ISNULL(a.Status,'P') ApprovalStatus,a.Reason,a.ApprovedBy
FROM dbo.Pd_SaleLine sl
JOIN dbo.Pd_Product p ON p.ProductId=sl.ProductId
JOIN dbo.Pd_Category c ON c.CategoryId=p.CategoryId
OUTER APPLY (SELECT TOP 1 * FROM dbo.Pd_GpApproval g WHERE g.ProductId=sl.ProductId AND (g.InvoiceNo=sl.InvoiceNo OR g.QuotationNo=sl.QuotationNo) ORDER BY g.ApprovalId DESC) a
WHERE sl.GPPct < c.MinGPPct;
GO

/* ---------- 6. Procedures ---------- */
/* รับเข้า: ปรับทุนเฉลี่ยเคลื่อนที่ */
CREATE OR ALTER PROCEDURE dbo.sp_Pd_Receive
  @ProductId INT, @Qty DECIMAL(12,2), @UnitCost DECIMAL(14,4), @DocNo VARCHAR(30)=NULL,
  @VendorPONo VARCHAR(20)=NULL, @Note NVARCHAR(300)=NULL, @User NVARCHAR(50)=NULL, @MoveDate DATE=NULL
AS
BEGIN
  SET XACT_ABORT ON; IF @Qty<=0 THROW 50001,N'จำนวนรับเข้าต้องมากกว่า 0',1;
  BEGIN TRAN;
    UPDATE dbo.Pd_Product WITH (UPDLOCK)
       SET AvgCost = CASE WHEN (CASE WHEN OnHand>0 THEN OnHand ELSE 0 END)+@Qty>0
                          THEN ((CASE WHEN OnHand>0 THEN OnHand ELSE 0 END)*AvgCost+@Qty*@UnitCost)/((CASE WHEN OnHand>0 THEN OnHand ELSE 0 END)+@Qty)
                          ELSE @UnitCost END,
           OnHand  = OnHand+@Qty, UpdatedAt=SYSDATETIME()
     WHERE ProductId=@ProductId;
    INSERT dbo.Pd_StockMove(MoveDate,MoveType,ProductId,Qty,UnitCost,DocNo,VendorPONo,Note,CreatedBy)
    VALUES (ISNULL(@MoveDate,CAST(GETDATE() AS DATE)),'GR',@ProductId,@Qty,@UnitCost,@DocNo,@VendorPONo,@Note,@User);
  COMMIT;
END
GO

/* จ่ายออก/ขาย: ตัดสต็อกที่ทุนเฉลี่ย และบันทึกบรรทัดขาย */
CREATE OR ALTER PROCEDURE dbo.sp_Pd_Issue
  @ProductId INT, @Qty DECIMAL(12,2), @InvoiceNo VARCHAR(30), @CustomerId VARCHAR(20),
  @UnitPrice DECIMAL(14,2), @SaleName NVARCHAR(100)=NULL, @QuotationNo VARCHAR(20)=NULL,
  @User NVARCHAR(50)=NULL, @InvoiceDate DATE=NULL, @AllowNegative BIT=0
AS
BEGIN
  SET XACT_ABORT ON; DECLARE @cost DECIMAL(14,4), @oh DECIMAL(12,2), @d DATE=ISNULL(@InvoiceDate,CAST(GETDATE() AS DATE));
  BEGIN TRAN;
    SELECT @cost=AvgCost,@oh=OnHand FROM dbo.Pd_Product WITH (UPDLOCK) WHERE ProductId=@ProductId;
    IF @oh<@Qty AND @AllowNegative=0 THROW 50002,N'สต็อกไม่พอ',1;
    UPDATE dbo.Pd_Product SET OnHand=OnHand-@Qty, UpdatedAt=SYSDATETIME() WHERE ProductId=@ProductId;
    INSERT dbo.Pd_StockMove(MoveDate,MoveType,ProductId,Qty,UnitCost,DocNo,CustomerId,CreatedBy)
    VALUES (@d,'IS',@ProductId,-@Qty,@cost,@InvoiceNo,@CustomerId,@User);
    INSERT dbo.Pd_SaleLine(InvoiceNo,InvoiceDate,QuotationNo,CustomerId,SaleName,ProductId,Qty,UnitPrice,UnitCostAtSale)
    VALUES (@InvoiceNo,@d,@QuotationNo,@CustomerId,@SaleName,@ProductId,@Qty,@UnitPrice,@cost);
  COMMIT;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_Pd_Adjust
  @ProductId INT, @Qty DECIMAL(12,2), @Note NVARCHAR(300), @User NVARCHAR(50)=NULL
AS
BEGIN
  SET XACT_ABORT ON; IF NULLIF(LTRIM(@Note),'') IS NULL THROW 50003,N'การปรับยอดต้องมีหมายเหตุ',1;
  DECLARE @seq INT=(SELECT COUNT(*)+1 FROM dbo.Pd_StockMove WHERE MoveType='ADJ');
  BEGIN TRAN;
    UPDATE dbo.Pd_Product SET OnHand=OnHand+@Qty, UpdatedAt=SYSDATETIME() WHERE ProductId=@ProductId;
    INSERT dbo.Pd_StockMove(MoveDate,MoveType,ProductId,Qty,UnitCost,DocNo,Note,CreatedBy)
    SELECT CAST(GETDATE() AS DATE),'ADJ',@ProductId,@Qty,AvgCost,'ADJ-'+RIGHT('00000'+CAST(@seq AS VARCHAR),5),@Note,@User
    FROM dbo.Pd_Product WHERE ProductId=@ProductId;
  COMMIT;
END
GO

/* สร้าง PO (DRAFT) จากรายการแนะนำ แยกตามผู้ขาย */
CREATE OR ALTER PROCEDURE dbo.sp_Pd_CreatePOFromSuggest
  @SupplierCode VARCHAR(10), @User NVARCHAR(50)=NULL, @VendorPONo VARCHAR(20)=NULL OUTPUT
AS
BEGIN
  SET XACT_ABORT ON;
  IF NOT EXISTS (SELECT 1 FROM dbo.v_Pd_ReorderSuggest WHERE SupplierCode=@SupplierCode) RETURN;
  DECLARE @yy CHAR(2)=RIGHT(CAST(YEAR(GETDATE()) AS VARCHAR),2);
  BEGIN TRAN;
    SELECT @VendorPONo='PO-V'+@yy+RIGHT('0000'+CAST(ISNULL(MAX(CAST(RIGHT(VendorPONo,4) AS INT)),0)+1 AS VARCHAR),4)
      FROM dbo.Pd_PurchaseOrder WITH (TABLOCKX) WHERE VendorPONo LIKE 'PO-V'+@yy+'%';
    INSERT dbo.Pd_PurchaseOrder(VendorPONo,SupplierCode,PODate,ETA,Status,CreatedBy)
    SELECT @VendorPONo,@SupplierCode,CAST(GETDATE() AS DATE),DATEADD(DAY,LeadDays,CAST(GETDATE() AS DATE)),'DRAFT',@User
      FROM dbo.Pd_Supplier WHERE SupplierCode=@SupplierCode;
    INSERT dbo.Pd_PurchaseOrderLine(VendorPONo,LineNo,ProductId,Qty,UnitCost)
    SELECT @VendorPONo,ROW_NUMBER() OVER (ORDER BY Sku),ProductId,SuggestQty,AvgCost
      FROM dbo.v_Pd_ReorderSuggest WHERE SupplierCode=@SupplierCode AND SuggestQty>0;
  COMMIT;
END
GO

/* รับของตาม PO: @Lines = JSON [{"line":1,"qty":5,"cost":420}] */
CREATE OR ALTER PROCEDURE dbo.sp_Pd_ReceivePO
  @VendorPONo VARCHAR(20), @Lines NVARCHAR(MAX), @DocNo VARCHAR(30)=NULL, @User NVARCHAR(50)=NULL
AS
BEGIN
  SET XACT_ABORT ON;
  DECLARE @r TABLE(LineNo SMALLINT, Qty DECIMAL(12,2), Cost DECIMAL(14,4));
  INSERT @r SELECT j.line,j.qty,j.cost FROM OPENJSON(@Lines) WITH (line SMALLINT, qty DECIMAL(12,2), cost DECIMAL(14,4)) j WHERE j.qty>0;
  BEGIN TRAN;
    DECLARE @ln SMALLINT,@q DECIMAL(12,2),@c DECIMAL(14,4),@pid INT,@rem DECIMAL(12,2);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
      SELECT r.LineNo, r.Qty, ISNULL(r.Cost,l.UnitCost), l.ProductId, l.Qty-l.QtyReceived
      FROM @r r JOIN dbo.Pd_PurchaseOrderLine l ON l.VendorPONo=@VendorPONo AND l.LineNo=r.LineNo;
    OPEN cur; FETCH NEXT FROM cur INTO @ln,@q,@c,@pid,@rem;
    WHILE @@FETCH_STATUS=0
    BEGIN
      IF @q>@rem SET @q=@rem;
      IF @q>0
      BEGIN
        EXEC dbo.sp_Pd_Receive @ProductId=@pid,@Qty=@q,@UnitCost=@c,@DocNo=@DocNo,@VendorPONo=@VendorPONo,@User=@User;
        UPDATE dbo.Pd_PurchaseOrderLine SET QtyReceived=QtyReceived+@q, UnitCost=@c WHERE VendorPONo=@VendorPONo AND LineNo=@ln;
      END
      FETCH NEXT FROM cur INTO @ln,@q,@c,@pid,@rem;
    END
    CLOSE cur; DEALLOCATE cur;
    UPDATE dbo.Pd_PurchaseOrder
       SET Status = CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.Pd_PurchaseOrderLine WHERE VendorPONo=@VendorPONo AND QtyReceived<Qty)
                         THEN 'RECEIVED' ELSE 'PARTIAL' END
     WHERE VendorPONo=@VendorPONo;
  COMMIT;
END
GO

/* ตรวจ GP ก่อนเสนอราคา: คืนค่า GP%, เกณฑ์, ราคาต่ำสุดที่ไม่ต้องขออนุมัติ */
CREATE OR ALTER PROCEDURE dbo.sp_Pd_CheckGP
  @ProductId INT, @UnitPrice DECIMAL(14,2), @Qty DECIMAL(12,2)=1
AS
SELECT p.Sku,p.ProductName,p.AvgCost,@UnitPrice UnitPrice,
       CAST(CASE WHEN @UnitPrice>0 THEN (@UnitPrice-p.AvgCost)/@UnitPrice*100 END AS DECIMAL(7,2)) GPPct,
       c.MinGPPct,
       CAST(CEILING(p.AvgCost/(1-c.MinGPPct/100.0)) AS DECIMAL(14,0)) FloorPrice,
       CASE WHEN @UnitPrice < p.AvgCost/(1-c.MinGPPct/100.0) THEN 1 ELSE 0 END NeedApproval,
       p.Available, CASE WHEN p.Available<@Qty THEN 1 ELSE 0 END ShortStock
FROM dbo.Pd_Product p JOIN dbo.Pd_Category c ON c.CategoryId=p.CategoryId
WHERE p.ProductId=@ProductId;
GO
