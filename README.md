## 1. Source Files
`po_api.dart`: Centralizes all Purchase Order related API endpoint paths.
`po_controller.dart`: Handles API calls, request payload construction, response normalization, and snackbar feedback.
`purchase_order_model.dart`: Defines Purchase Order domain models and JSON parsing/serialization.
`po_list_screen.dart`: Main listing screen, location selector, filters, pagination, and navigation to create/detail view.
`po_form_screen.dart`: Purchase Order create/detail form, cascading dropdowns, line item entry, product search, TRX items, approval log, and save flow.
`theme.dart`: Module-specific colors, theme data, status badge colors, and approval-log colors.


## 2. Architecture Overview
The module follows a simple UI -> controller -> API pattern:

1. `POListScreen` loads required lookup data on startup.
2. User selects a location.
3. `POController.getPurchaseOrders()` builds the query string and calls the listing endpoint.
4. Raw listing rows are converted into `PurchaseOrder` objects using `PurchaseOrder.fromJson()`.
5. Tapping a purchase order calls `POController.getPurchaseOrderDetail()` and opens `POFormScreen` in view-only mode.
6. Creating a new purchase order opens `POFormScreen` without an existing order.
7. `POFormScreen` loads locations and cascading purchase options.
8. On save, form state is converted into a `PurchaseOrder` object and submitted through `POController.savePurchaseOrder()`.


## 3. API Endpoint Map
All endpoint constants are defined in `PurchaseOrderApi` in `POController.dart`.
|  Constant    |          Backend action              |                    Used for                         |
|listing       | get_all_purchase_order               | Fetch paginated/filterable PO listing.              |
|submit        | submit_purchase_order                | Create new PO.                                      |
|locations     | get_location_list                    | Load available locations.                           |
|options       | purchase_order_requirement           | Load cascading form options for a selected location.|
|products      | ajax_search_purchase_product_listing | Product search for filters and line items.          |
|productDetail | ajax_get_product_detail              | Product detail, UOM, balance, and PR document data. |
|detail        | purchase_order_detail                | Fetch full detail for selected PO.                  |
|poStatus      | get_po_status                        | Load PO status filter options.                      |
|vendorListing | get_all_vendor_list                  | Load vendor filter options.                         |


## 4. Controller Responsibilities
`POController` provides the API boundary for the module.

### Listing
`getPurchaseOrders()` accepts filters and pagination values. It serializes them into query parameters and appends them to the listing endpoint. The current supported parameters are:
- `id`
- `org_sub_id`
- `pstatus`
- `astatus`
- `vendor`
- `docno`
- `sdate`
- `edate`
- `product_id`
- `ref_docno`
- `remark`
- `item_remark`
- `limit`
- `skip`

Status mapping is performed in `POListScreen` before calling the controller:
|  Status name    |         Payload          |
|Posted           | `pstatus = 11`           |
|Pending Approval | `astatus = 4`            |
|Released         | `pstatus = 99`           |
|Partial          | `pstatus = 9`            |
|Completed        | `pstatus = 10`           |
|All              | blank status values (='')|

### Detail
`getPurchaseOrderDetail()` posts `form_id` to the detail endpoint. This is important because the backend permission flow expects `form_id` in the POST body for detail access.

### Save
`savePurchaseOrder()` handles create:
- Create uses `PurchaseOrderApi.submit`.
- Dates are formatted as `YYYY-MM-DD`, not full ISO timestamps.
- Line items are submitted under `items`.
- TRX rows are submitted under `trx`.
- Success/failure feedback is shown through `CommonUtils.showSnackBar()`.

### Lookup and Integration Calls
The controller also exposes:
- `getPoStatuses()`
- `getVendors()`
- `getLocations()`
- `getPurchaseOptions(locationId)`
- `searchProducts(searchText)`
- `getProductDetail(productId, locationId)`


## 5. Data Model Details
### `PurchaseOrder`
Represents the PO header and related child data.
Important fields:
- `id`: encoded backend record id, used for detail.
- `docNo`: document number displayed in listing/detail.
- `poDate`, `docDate`, `expectedReceiptDate`.
- `location`, `vendor`, `currency`, `urgency`, `mode`: backend ids/tids used for form matching/submission.
- `locationName`, `vendorName`: readable labels for display.
- `refNo`, `remark`, `totalAmount`, `status`, `exchangeRate`.
- `lineItems`: list of `POLineItem`.
- `trxItems`: list of `POTrxLineItem`.
- `approvalLogs`: list of `POApprovalLog`.

The parser intentionally supports multiple backend key shapes from listing and detail APIs. For example:
- Document number can come from `Document`, `docno`, `sdocno`, or `doc_no`.
- Location can come from `org_sub_id`, `org_id`, `organization`, `loc_id`, `location_id`, or `location`.
- Vendor can come from `vendor` or `vendor_id`.
- Detail items can be flat arrays or wrapped in numeric-key objects.

### `POLineItem`
Represents product line rows. It supports product id, variation, PR references, balance quantities, UOM, unit price, amount, and remark.
The parser handles both listing-style and detail-style fields, including:
- Product labels: `Product`, `product_name`, `pd_name`, `product_code`.
- Quantity fields: `Quantity`, `qty`, `os_bal`, `po_qty`, `uqty`.
- UOM fields: `UOM`, `uom_code`, `buom_code`, `uom`.
- Price fields: `U.Price`, `uprice`, `u_price`, `price`.

### `POTrxLineItem`
Represents additional transaction rows such as discount or freight charge.

### `POApprovalLog`
Represents approval history rows. The parser supports both normalized keys and backend display keys such as `Action By` and `Action Date`.


## 6. List Screen Behavior
`POListScreen` is the main entry point.
Startup behavior:
1. Fetch locations.
2. Fetch PO statuses.
3. Fetch vendors.
4. Select the first location by default.
5. Fetch the first page of purchase orders for the selected location.

Main UI areas:
- App bar with create and filter actions.
- Location bar.
- Collapsible advanced filter panel.
- Purchase order card list.
- Pagination controls.

Advanced filters:
- Status chips.
- Vendor dropdown.
- Document number/reference number text field.
- Product picker bottom sheet.
- PR document text field.
- Remark text field.
- Item remark text field.
- Start/end date pickers.

Pagination:
- Page size is fixed at 30.
- `_skip` is calculated as `(currentPage - 1) * pageSize`.
- If the backend does not return total count metadata, the UI assumes another page exists when a full page is returned. This prevents the Next button from being disabled too early.

Detail navigation:
- Tapping a card loads the full detail using `form_id`.
- The screen classifies mixed detail response rows into product items, TRX rows, and approval log rows before creating the full `PurchaseOrder` object.
- If detail loading fails, the app still opens the form using the listing-level order data as fallback.


## 7. Form Screen Behavior
`POFormScreen` supports two modes:
- Create mode: `widget.order == null`.
- View mode: `widget.order != null`.

### Initialization
On init:
- Header text controllers are initialized.
- Dates are initialized from the existing order or current date.
- Line items are restored from the order or initialized with one blank row.
- TRX items are restored from the order or initialized as empty.
- Locations are fetched.
- If viewing an existing order, the saved location is matched and cascading options are loaded for that location.

### Cascading Options
`_fetchCascadingOptions()` loads option lists based on the selected location:
- Currency
- Vendor
- Urgency
- Mode
- TRX code
- UOM list
- Location/base currency data
- Exchange rate
In create mode, the first available values are selected automatically. In view/detail mode, the implementation tries to match saved values by id, code, name, label, or partial readable name.

### Product Line Items
Users select a product through a bottom-sheet search. After product selection:
1. Product id/name are stored.
2. Existing product detail fields are reset.
3. `getProductDetail()` is called with selected product id and location id.
4. Product detail fills:
   - Product id
   - Variation
   - DID
   - Description
   - Unit price
   - PO Qty
   - PR Qty
   - Stock
   - UOM options
   - PR document options
Line item fields are locked when `item.isSaved == true`. The user toggles the save icon per line item before submitting the full PO. `_handleSave()` blocks submission if any line item remains unsaved.

### TRX Items
TRX rows support:
- TRX code dropdown.
- Amount.
- Remark.

`_calculateGrossTotal()` adds normal TRX amounts and subtracts discount rows when the selected TRX label/code contains `DISCOUNT`.

### View-Only Mode
When opened with an existing order:
- Header fields are read-only.
- Line item fields are non-interactive.
- Add/remove/save controls are hidden.
- Sticky footer shows total amount only.
- Approval log section is available and expandable when logs exist.


## 8. Save Payload Contract
The save payload is built in `POController.savePurchaseOrder()`.
(sample) Header payload:
```json
{
  "form_id": "MFZsenBtd2tpUWdrc3FRU3hyd1FTZz09",
  "organization": "NEt5N3hZZVBqbTE5bmtRK3BzbVZMQT09",
  "refno": "",
  "mode": "eUQ1eC94REFWN29LNE1BRjFtVGUwQT09",
  "po_date": "2026-06-25",
  "exp_dt": "2026-06-26",
  "vendor": "Ty9SYS9OM1ZWNHFIMXE5eEpIYWJyZz09",
  "contrator": "",
  "currency": "eUQ1eC94REFWN29LNE1BRjFtVGUwQT09",
  "exrate": 0.0018
  "bcurrency": "NEt5N3hZZVBqbTE5bmtRK3BzbVZMQT09",
  "urgency": "NEt5N3hZZVBqbTE5bmtRK3BzbVZMQT09",
  "dept": "",
  "remark": "mobile testing 5"
}
```

Line item payload under `items`:
```json
{
  "ptid": 1,
  "id": "1890",
  "variation": "0",
  "did": "U2dRKzdkQUZ0Q0pnR0ZKbUFhUXM1UT09",
  "qty": 1,
  "uom": "NEt5N3hZZVBqbTE5bmtRK3BzbVZMQT09",
  "remark": "mobile testing 5",
  "available": 0,
  "ref_qty": 75,
  "price": 5.6,
  "ref_hid": "REZYaU9pWTFDNkU1WlE0cHBHZ0Q3Zz09",
  "ref_did": "WkIxYlo4cjNISXR3L3FDN0ZPdG5jQT09",
  "ref_doc": "RTdkbGRKTm9MNXUyQ1VaUVIyZFl0UT09"
}
```

TRX payload under `trx`:
```json
{
  "TRX Code":"FREIGHT CHARGE",
  "amount": 50.00000,
  "plus_minus":"1"
  "remark": "mobile testing 5"
}
```
