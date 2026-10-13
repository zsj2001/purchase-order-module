import 'package:flutter/material.dart';
import '../../extension/context_extension.dart';

enum POStatus { all, draft, pendingApproval, posted, partial, completed, cancelled }

extension POStatusExt on POStatus {
  /// Returns a localized label. Requires BuildContext to access the current language.
  String label(BuildContext context) {
    switch (this) {
      case POStatus.all:
        return context.str.all;
      case POStatus.draft:
        return context.str.draft;
      case POStatus.pendingApproval:
        return context.str.pendingApproval;
      case POStatus.posted:
        return context.str.posted;
      case POStatus.partial:
        return context.str.partial;
      case POStatus.completed:
        return context.str.completed;
      case POStatus.cancelled:
        return context.str.cancel;
    }
  }

  /// Raw API value — never localized, used only for backend filtering.
  String get apiValue {
    switch (this) {
      case POStatus.all:
        return 'All';
      case POStatus.draft:
        return 'Draft';
      case POStatus.pendingApproval:
        return 'Pending Approval';
      case POStatus.posted:
        return 'Posted';
      case POStatus.partial:
        return 'Partial';
      case POStatus.completed:
        return 'Complete';
      case POStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class POLineItem {
  final String productNameCodeSku;
  final String productId; // API product id — sent on submit
  final String variation; // product variation — sent on submit
  final String did; // product did — sent on submit
  final String refHid; // selected doc hid — sent on submit
  final String refDid; // selected doc id — sent on submit
  final String description;
  final String prDoc;
  final int poQty;
  final int prQty;
  final int stockQty;
  final int availableQty;
  final String uom;
  final double uPrice;
  final double amount;
  final String remark;
  bool isSelected;
  bool isSaved;

  POLineItem({
    required this.productNameCodeSku,
    this.productId = '',
    this.variation = '',
    this.did = '',
    this.refHid = '',
    this.refDid = '',
    this.description = '',
    this.prDoc = '',
    this.poQty = 0,
    this.prQty = 0,
    this.stockQty = 0,
    this.availableQty = 0,
    this.uom = 'PCS',
    this.uPrice = 0.0,
    this.amount = 0.0,
    this.remark = '',
    this.isSelected = false,
    this.isSaved = true,
  });

  factory POLineItem.fromJson(Map<String, dynamic> json) {
    return POLineItem(
      productNameCodeSku: json['Product']?.toString() ??
          json['product_name']?.toString() ??
          json['pd_name']?.toString() ??
          json['product_code']?.toString() ??
          json['productNameCodeSku']?.toString() ??
          '',
      productId: json['id']?.toString() ??
          json['product_id']?.toString() ??
          '',
      variation: json['variation']?.toString() ?? '',
      did: json['did']?.toString() ?? '',
      refHid: json['ref_hid']?.toString() ?? json['hid']?.toString() ?? '',
      refDid: json['ref_did']?.toString() ?? json['ref_doc']?.toString() ?? '',
      description: json['Description']?.toString() ??
          json['description']?.toString() ??
          json['pd_name']?.toString() ??
          '',
      prDoc: json['pr_doc']?.toString() ?? json['ref_docno']?.toString() ?? '',
      poQty: int.tryParse(json['os_bal']?.toString() ??
          json['po_qty']?.toString() ??
          json['uqty']?.toString() ??
          '0') ??
          0,
      prQty: double.tryParse(json['ref_bal_qty']?.toString() ??
          json['pr_qty']?.toString() ??
          json['ref_qty']?.toString() ??
          '0')?.toInt() ??
          0,
      stockQty: int.tryParse(json['On Hand']?.toString() ??
          json['stock_qty']?.toString() ??
          json['available']?.toString() ??
          '0') ??
          0,
      availableQty: double.tryParse(json['Quantity']?.toString() ??
          json['qty']?.toString() ??
          '0')
          ?.toInt() ??
          0,
      uom: json['UOM']?.toString() ??
          json['uom_code']?.toString() ??
          json['buom_code']?.toString() ??
          json['uom']?.toString() ??
          'PCS',
      uPrice: double.tryParse(json['U.Price']?.toString() ??
          json['uprice']?.toString() ??
          json['u_price']?.toString() ??
          json['price']?.toString() ??
          '0.0') ??
          0.0,
      amount: double.tryParse(json['Amount']?.toString() ??
          json['amount']?.toString() ??
          '0.0') ??
          0.0,
      remark: json['Remark']?.toString() ?? json['remark']?.toString() ?? '',
      isSaved: json['isSaved'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_name': productNameCodeSku,
      'id': productId,
      'product_id': productId,
      'variation': variation,
      'did': did,
      'ref_hid': refHid,
      'ref_did': refDid,
      'description': description,
      'pr_doc': prDoc,
      'ref_doc': prDoc,
      'po_qty': poQty,
      'pr_qty': prQty,
      'ref_qty': prQty,
      'stock_qty': stockQty,
      'available': stockQty,
      'qty': availableQty,
      'uom': uom,
      'u_price': uPrice,
      'price': uPrice,
      'amount': amount,
      'remark': remark,
    };
  }
}

class POTrxLineItem {
  final String code;
  final double amount;
  final String remark;

  POTrxLineItem({
    required this.code,
    required this.amount,
    this.remark = '',
  });

  factory POTrxLineItem.fromJson(Map<String, dynamic> json) {
    return POTrxLineItem(
      // 'TRX Code' is the raw key returned by the detail API when the mixed
      // item array is not pre-split. 'code' / 'trx_code' are the normalised
      // keys we write after splitting in _openUpdate.
      code: json['code']?.toString() ??
          json['trx_code']?.toString() ??
          json['TRX Code']?.toString() ??
          json['trx_id']?.toString() ??
          json['id']?.toString() ??
          '',
      amount: double.tryParse(json['amount']?.toString() ??
          json['Amount']?.toString() ??
          json['amt']?.toString() ??
          '0.0') ??
          0.0,
      remark: json['remark']?.toString() ?? json['Remark']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'trx_code': code,
      'amount': amount,
      'remark': remark,
    };
  }
}

class POApprovalLog {
  final String action;
  final String actionBy;
  final String remark;
  final String actionDate;

  POApprovalLog({
    required this.action,
    required this.actionBy,
    required this.remark,
    required this.actionDate,
  });

  factory POApprovalLog.fromJson(Map<String, dynamic> json) {
    return POApprovalLog(
      action: json['action']?.toString() ?? json['Action']?.toString() ?? '',
      actionBy: json['action_by']?.toString() ?? json['Action By']?.toString() ?? json['username']?.toString() ?? '',
      remark: json['remark']?.toString() ?? json['Remark']?.toString() ?? '',
      actionDate: json['action_dt']?.toString() ?? json['Action Date']?.toString() ?? json['act_dt']?.toString() ?? '',
    );
  }
}

class PurchaseOrder {
  final String id; // encoded record id — used for detail/update API calls
  final String docNo;
  final DateTime poDate;
  final DateTime docDate;
  final String location; // tid — used for form dropdown matching
  final String locationName; // readable — displayed in list card
  final String vendor; // tid — used for form dropdown matching
  final String vendorName; // readable — displayed in list card
  final String refNo;
  final String currency; // tid — used for form dropdown matching
  final String urgency; // tid — used for form dropdown matching
  final String mode; // tid — used for form dropdown matching
  final DateTime? expectedReceiptDate;
  final String remark;
  final double totalAmount;
  final String status;
  final DateTime? createdOn;
  final List<POLineItem> lineItems;
  final List<POTrxLineItem> trxItems;
  final List<POApprovalLog> approvalLogs;
  final double exchangeRate;

  PurchaseOrder({
    this.id = '',
    required this.docNo,
    required this.poDate,
    required this.docDate,
    required this.location,
    this.locationName = '',
    required this.vendor,
    this.vendorName = '',
    this.refNo = '',
    this.currency = '',
    this.urgency = '',
    this.mode = '',
    this.expectedReceiptDate,
    this.remark = '',
    this.totalAmount = 0.0,
    this.status = 'Draft',
    this.createdOn,
    this.lineItems = const [],
    this.trxItems = const [],
    this.approvalLogs = const [],
    this.exchangeRate = 1.0,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return null;
      }
    }

    // For location and vendor, prefer tid fields for form dropdown matching.
    // Also store readable names separately for list card display.
    //
    // Listing API keys:  docno, vendor_name, loc_name, currency_code, status_name
    // Detail API keys:   vendor (tid), org_sub_id (tid), currency (tid), urgency (tid), md (tid)
    final String locationTid = json['org_sub_id']?.toString() ??
        //json['org_id']?.toString() ??
        json['organization']?.toString() ??
        json['loc_id']?.toString() ??
        json['location_id']?.toString() ??
        json['location']?.toString() ??
        '';
    final String locationReadable = json['loc_name']?.toString() ??
        json['location_name']?.toString() ??
        json['Location']?.toString() ??
        locationTid;

    final String vendorTid = json['vendor']?.toString() ??
        json['vendor_id']?.toString() ??
        '';
    final String vendorReadable = json['vendor_name']?.toString() ??
        json['vname']?.toString() ??
        json['Vendor']?.toString() ??
        vendorTid;

    final String currencyTid = json['currency']?.toString() ??
        json['currency_id']?.toString() ??
        json['currency_code']?.toString() ??
        json['Currency']?.toString() ??
        '';

    final String urgencyTid = json['urgency']?.toString() ??
        json['urgency_id']?.toString() ??
        json['urgency_name']?.toString() ??
        json['Urgency']?.toString() ??
        '';

    final String modeTid = json['md']?.toString() ??
        json['mode']?.toString() ??
        json['mode_id']?.toString() ??
        json['md_name']?.toString() ??
        json['Mode']?.toString() ??
        '';

    // Parse line items from various possible payload structures
    List<POLineItem> extractedItems = [];
    final dynamic itemsPayload = json['item'] ??
        json['items'] ??
        json['detail'] ??
        json['line_items'] ??
        [];
    if (itemsPayload is List) {
      for (var element in itemsPayload) {
        if (element is Map<String, dynamic>) {
          // Collect all numeric keys — the detail API wraps multiple line items
          // inside a single object using numeric string keys:
          //   [{"0": {...item0...}, "1": {...item1...}, "name": "Product Listing"}]
          // The old code used firstWhere which only extracted the first item.
          // We must iterate ALL numeric keys to get every line item.
          final numericKeys = element.keys
              .where((k) => int.tryParse(k) != null)
              .toList()
            ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

          if (numericKeys.isNotEmpty) {
            for (final k in numericKeys) {
              if (element[k] is Map) {
                extractedItems.add(POLineItem.fromJson(
                    Map<String, dynamic>.from(element[k] as Map)));
              }
            }
          } else {
            // Flat structure — no numeric keys, the element itself is a line item
            extractedItems.add(POLineItem.fromJson(element));
          }
        }
      }
    }

    // Parse transaction items
    List<POTrxLineItem> extractedTrx = [];
    final dynamic trxPayload = json['trx_items'] ??
        json['trx'] ??
        json['trx_detail'] ??
        [];
    if (trxPayload is List) {
      extractedTrx = trxPayload
          .whereType<Map<String, dynamic>>()
          .map((e) => POTrxLineItem.fromJson(e))
          .toList();
    }

    // Parse approval log entries. Same wrapper pattern the backend uses for
    // line items: either a List containing one object keyed "0","1",.. + a
    // "name" label, OR — as returned directly by the detail endpoint — a
    // single Map shaped like {"0": {...}, "1": {...}, "name": "Approval Log"}.
    List<POApprovalLog> extractedLogs = [];
    final dynamic logsPayload = json['approval_log'] ??
        json['approval_logs'] ??
        json['logs'] ??
        json['history'] ??
        [];

    List<Map<String, dynamic>> logEntries = [];
    if (logsPayload is List) {
      for (final element in logsPayload) {
        if (element is! Map) continue;
        final Map<String, dynamic> map = Map<String, dynamic>.from(element);
        final numericKeys = map.keys.where((k) => int.tryParse(k) != null).toList()
          ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
        if (numericKeys.isNotEmpty) {
          for (final k in numericKeys) {
            if (map[k] is Map) logEntries.add(Map<String, dynamic>.from(map[k] as Map));
          }
        } else {
          logEntries.add(map);
        }
      }
    } else if (logsPayload is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(logsPayload);
      final numericKeys = map.keys.where((k) => int.tryParse(k) != null).toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      for (final k in numericKeys) {
        if (map[k] is Map) logEntries.add(Map<String, dynamic>.from(map[k] as Map));
      }
    }
    extractedLogs = logEntries.map((e) => POApprovalLog.fromJson(e)).toList();

    return PurchaseOrder(
      id: json['id']?.toString() ??
          json['form_id']?.toString() ??
          '',
      docNo: json['Document']?.toString() ??
          json['docno']?.toString() ??
          json['sdocno']?.toString() ??
          json['doc_no']?.toString() ??
          '',
      poDate: parseDate(json['Date'] ?? json['doc_dt'] ?? json['po_date']) ??
          DateTime.now(),
      docDate: parseDate(json['doc_date'] ?? json['created_at']) ?? DateTime.now(),
      location: locationTid.isNotEmpty ? locationTid : locationReadable,
      locationName: locationReadable,
      vendor: vendorTid.isNotEmpty ? vendorTid : vendorReadable,
      vendorName: vendorReadable,
      refNo: json['refno']?.toString() ??
          json['ref_no']?.toString() ??
          '',
      currency: currencyTid,
      urgency: urgencyTid,
      mode: modeTid,
      expectedReceiptDate: parseDate(json['Expected Receive Date'] ??
          json['exp_dt']),
      remark: json['remark']?.toString() ?? '',
      totalAmount: double.tryParse(
          json['total_amount']?.toString() ??
              json['grand_total']?.toString() ??
              '0') ??
          0.0,
      exchangeRate: double.tryParse(
          json['exrate']?.toString() ??
              json['ex_rate']?.toString() ??
              json['exchange_rate']?.toString() ??
              '1.0') ??
          1.0,
      status: json['status_name']?.toString() ??
          json['status']?.toString() ??
          'Draft',
      createdOn: parseDate(json['created_at'] ?? json['created_on']),
      lineItems: extractedItems,
      trxItems: extractedTrx,
      approvalLogs: extractedLogs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'form_id': id,
      'doc_no': docNo,
      'Document': docNo,
      'po_date': poDate.toIso8601String(),
      'doc_date': docDate.toIso8601String(),
      'location_id': location,
      'location': location,
      'location_name': locationName,
      'vendor_id': vendor,
      'vendor': vendor,
      'vendor_name': vendorName,
      'ref_no': refNo,
      'currency': currency,
      'urgency': urgency,
      'mode': mode,
      'exp_dt': expectedReceiptDate?.toIso8601String(),
      'remark': remark,
      'total_amount': totalAmount,
      'grand_total': totalAmount,
      'status': status,
      'created_on': createdOn?.toIso8601String(),
      'exrate': exchangeRate,
      'exchange_rate': exchangeRate,
      'items': lineItems.map((item) => item.toJson()).toList(),
      'trx_items': trxItems.map((item) => item.toJson()).toList(),
    };
  }
}