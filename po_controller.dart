import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:base_template/common/utils/common_api.dart';
import 'package:base_template/common/utils/common_utils.dart';
import 'po_model.dart';
import 'po_api.dart';

class POController {
  /// Fetches the list of Purchase Orders based on filters.
  /// [id]        — optional, filter by a specific PO record id.
  /// [orgSubId]  — optional, filter by location/organisation id.
  /// [status]    — optional status filter (e.g. 'All', 'Draft', 'Posted').
  /// [limit]     — how many records to return per page (default 30).
  /// [skip]      — how many records to skip (i.e. page * limit offset).
  /// Fetches the list of Purchase Orders.
  /// Status filtering:
  ///   pstatus — posting status id  (11=Posted, 9=Partial, 10=Completed, 99=Released)
  ///   astatus — approval status id (4=Pending Approval)
  /// Vendor: vendor id (encoded) from getVendors()
  /// Date:   sdate/edate action date range, YYYY-MM-DD
  /// Docno:  ref document number
  /// Product: product id filter (product_id)
  /// Remark: general order remark filter string
  /// ItemRemark: individual line item remark filter string
  /// RefDocno: PR document number filter
  Future<Map<String, dynamic>> getPurchaseOrders({
    String? id,
    String? orgSubId,
    String pstatus = '',
    String astatus = '',
    String vendor  = '',
    String docno   = '',
    String sdate   = '',
    String edate   = '',
    String productId  = '',
    String refDocno   = '',
    String remark     = '',
    String itemRemark = '',
    int limit = 30,
    int skip  = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'skip':  skip.toString(),
    };

    if (id       != null && id.isNotEmpty)       queryParams['id']         = id;
    if (orgSubId != null && orgSubId.isNotEmpty) queryParams['org_sub_id'] = orgSubId;
    if (pstatus.isNotEmpty)                      queryParams['pstatus']    = pstatus;
    if (astatus.isNotEmpty)                      queryParams['astatus']    = astatus;
    if (vendor.isNotEmpty)                       queryParams['vendor']     = vendor;
    if (docno.isNotEmpty)                        queryParams['docno']      = docno.trim();
    if (sdate.isNotEmpty)                        queryParams['sdate']      = sdate;
    if (edate.isNotEmpty)                        queryParams['edate']      = edate;
    if (productId.isNotEmpty)                    queryParams['product_id']  = productId.trim();
    if (refDocno.isNotEmpty)                     queryParams['ref_docno']   = refDocno.trim();
    if (remark.isNotEmpty)                       queryParams['remark']      = remark.trim();
    if (itemRemark.isNotEmpty)                   queryParams['item_remark'] = itemRemark.trim();

    // Encode params into the URL so PHP reads them via $_GET/$_REQUEST.
    final val = await CommonApi().post(api: PurchaseOrderApi.listing, data: queryParams, method: 'get', responseType: ResponseType.plain, decode: true);
    return val;
  }

  /// Fetches the full detail of a single Purchase Order by its record id.
  /// [formId] — the `id` field from the listing response.
  /// Uses POST with form_id in the request body so the backend permission
  /// check (action 1244 / vact=view) passes correctly — the same auth
  /// flow that all other IVMS endpoints rely on.
  Future<Map<String, dynamic>> getPurchaseOrderDetail({
    required String formId,
  }) async {
    // POST with form_id in the body — the backend resolves the permission
    // check against the session user when form_id arrives as a POST field.
    final val = await CommonApi().post(
      api: PurchaseOrderApi.detail,
      data: {'form_id': formId},
      method: 'get',
    );

    final dynamic raw = val['data'];
    final Map<String, dynamic> map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : {};

    if (map['item'] is List) {
      final sections = map['item'] as List;
      for (final section in sections) {
        if (section is Map) {
          final name = section['name'] ?? 'Unknown';
          final count = section.keys.where((k) => int.tryParse(k.toString()) != null).length;
        }
      }
    }
    return {'success': val['success'] ?? map.isNotEmpty, 'data': map};
  }


  /// Handles both Create and Update logic for a Purchase Order.
  Future<void> savePurchaseOrder({
    required BuildContext context,
    required PurchaseOrder order,
    required bool isUpdate,
    required Function(PurchaseOrder) onSuccess,
    String bcurrency    = '',
    double exchangeRate = 1.0,
  }) async {
    // Backend requires plain YYYY-MM-DD — NOT ISO8601 full timestamp
    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final expectedReceiveDate = fmtDate(order.expectedReceiptDate ?? DateTime.now());
    final Map<String, dynamic> data = {
      // form_id is required by the update endpoint so the backend knows which record to modify. Without it the web version never sees the change.
      if (isUpdate && order.id.isNotEmpty) 'form_id': order.id,
      'organization': order.location,
      'refno':        order.refNo,
      'mode':         order.mode,
      'po_date':      fmtDate(order.poDate),
      'exp_dt': expectedReceiveDate,
      'vendor':       order.vendor,
      'contrator':    '',
      'currency':     order.currency,
      'exrate':       exchangeRate,
      'bcurrency':    bcurrency,
      'urgency':      order.urgency,
      'dept':         '',
      'remark':       order.remark,
      'items': order.lineItems.asMap().entries.map((e) {
        final i = e.value;
        return {
          'ptid':      e.key+1,
          'id':        i.productId,
          'variation': i.variation,
          'did':       i.did,
          'qty':       i.availableQty,
          'uom':       i.uom,
          'remark':    i.remark,
          'available': i.stockQty,
          'ref_qty':   i.prQty,
          'price':     i.uPrice,
          'ref_hid':   i.refHid,
          'ref_did':   i.refDid,
          'ref_doc':   i.prDoc,
        };
      }).toList(),
      'trx': order.trxItems.map((t) => {
        'id':     t.code,
        'amount': t.amount,
        'remark': t.remark,
      }).toList(),
    };

    const String apiEndpoint = PurchaseOrderApi.submit;
    final response = await CommonApi().post(
      api: apiEndpoint,
      data: data,
      context: context,
    );

    if (response!= null && (response['success'] ?? false)) {
      CommonUtils.showSnackBar(
        isUpdate ? 'Order updated successfully' : 'Order created successfully',
        'success',
        context,
      );
      onSuccess(order);
    } else {
      CommonUtils.showSnackBar(
        response?['message'] ?? 'Failed to save purchase order',
        'danger',
        context,
      );
    }
  }

  /// Fetches the list of PO statuses for the filter dropdown.
  /// Each item has at least: { 'id': '11', 'name': 'Posted', ... }
  Future<Map<String, dynamic>> getPoStatuses() async {
    final val = await CommonApi().post(api: PurchaseOrderApi.poStatus, method: 'get', responseType: ResponseType.plain, decode: true);
    final List<dynamic> list = val['data'] is List ? val['data'] : [];
    return {'success': list.isNotEmpty, 'data': list};
  }

  /// Fetches the vendor list for the filter dropdown.
  Future<Map<String, dynamic>> getVendors() async {
    final val = await CommonApi().post(api: PurchaseOrderApi.vendorListing, method: 'get');
    final List<dynamic> list = val['data'] is List ? val['data'] : [];
    return {'success': list.isNotEmpty, 'data': list};
  }

  Future<Map<String, dynamic>> getLocations() async {
    final val = await CommonApi().post(api: PurchaseOrderApi.locations, method: 'get', responseType: ResponseType.plain, decode: true);
    final List<dynamic> list = val['data'] is List ? val['data'] : [];
    return {'success': list.isNotEmpty, 'data': list};
  }

  Future<Map<String, dynamic>> getPurchaseOptions({required String locationId}) async {
    final val = await CommonApi().post(
      api: PurchaseOrderApi.options,
      data: {'organization': locationId},
      method: 'get',
    );
    final dynamic raw = val['data'];
    final Map<String, dynamic> map = raw is Map ? Map<String, dynamic>.from(raw) : {};
    return {'success': val['success'] ?? map.isNotEmpty, 'data': map};
  }

  Future<Map<String, dynamic>> searchProducts({required String searchText}) async {
    final val = await CommonApi().post(
      api: PurchaseOrderApi.products,
      data: {'data': searchText},
      method: 'get',
    );
    final List<dynamic> list = val['data'] is List ? val['data'] : [];
    return {'success': true, 'data': list};
  }

  Future<Map<String, dynamic>> getProductDetail({
    required String productId,
    required String locationId,
  }) async {
    final String today = DateTime.now().toIso8601String().split('T')[0];
    final val = await CommonApi().post(
      api: PurchaseOrderApi.productDetail,
      data: {'id': productId, 'return': 'data', 'loc': locationId, 'form': 'po', 'date': today},
      method: 'get',
    );
    final dynamic raw = val['data'];
    final Map<String, dynamic> map = raw is Map ? Map<String, dynamic>.from(raw) : {};
    return {'success': val['success'] ?? map.isNotEmpty, 'data': map};
  }
}