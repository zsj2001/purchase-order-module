import 'package:flutter/material.dart';
import 'package:base_template/module/purchase_order/po_model.dart';
import 'package:base_template/module/purchase_order/theme.dart';
import '../../extension/context_extension.dart';
import 'package:base_template/module/purchase_order/po_controller.dart';
import 'package:base_template/common/utils/common_utils.dart';

class POFormScreen extends StatefulWidget {
  final PurchaseOrder? order;
  final Function(PurchaseOrder) onSave;
  final String? initialLocationId;
  final String? initialLocationLabel;

  const POFormScreen({super.key, this.order, required this.onSave, this.initialLocationId, this.initialLocationLabel});

  @override
  State<POFormScreen> createState() => _POFormScreenState();
}

class _POFormScreenState extends State<POFormScreen> {
  final POController _controller = POController();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _refNoCtrl, _remarkCtrl;
  late TextEditingController _exRateCtrl;
  late DateTime _poDate, _expectedReceiptDate;
  late List<_LineItemForm> _lineItems;
  late List<_TrxLineItemForm> _trxItems;

  // Location
  String _locationId = '';
  String _locationLabel = '';
  List<_POOption> _locations = [];

  // Options populated after location is chosen
  List<_POOption> _vendors = [];
  List<_POOption> _currencies = [];
  List<_POOption> _urgencies = [];
  List<_POOption> _modes = [];
  List<_POOption> _trxCodes = [];
  List<String> _uomOptions = [];

  // Selected option objects
  _POOption? _selectedVendor;
  _POOption? _selectedCurrency;
  _POOption? _selectedUrgency;
  _POOption? _selectedMode;

  // Exchange rate and base currency returned by the API
  double _exchangeRate = 1.0;
  String _bcurrency = ''; // base currency tid
  _POOption? _defaultCurrency; // location's base currency option

  bool _isLoadingLocations  = false;
  bool _isLoadingOptions    = false;
  bool _isSaving            = false;
  bool _approvalLogExpanded = false;
  bool _vendorError         = false;
  bool _urgencyError        = false;

  @override
  void initState() {
    super.initState();
    final o = widget.order;

    _refNoCtrl = TextEditingController(text: o?.refNo ?? '');
    _remarkCtrl = TextEditingController(text: o?.remark ?? '');
    _exRateCtrl = TextEditingController(text: '1.0');
    _poDate = o?.poDate ?? DateTime.now();
    _expectedReceiptDate = o?.expectedReceiptDate ?? DateTime.now();

    _lineItems = o != null && o.lineItems.isNotEmpty
        ? o.lineItems.map<_LineItemForm>((item) => _LineItemForm.fromItem(item)).toList()
        : [_LineItemForm()];

    _trxItems = o != null && o.trxItems.isNotEmpty
        ? o.trxItems.map((trxItem) => _TrxLineItemForm.fromItem(trxItem)).toList()
        : [];
    _fetchInitialLocations(prefillOrder: o);
  }

  @override
  void dispose() {
    _refNoCtrl.dispose();
    _remarkCtrl.dispose();
    _exRateCtrl.dispose();
    for (final item in _lineItems) {
      item.dispose();
    }
    for (final item in _trxItems) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchInitialLocations({PurchaseOrder? prefillOrder}) async {
    setState(() => _isLoadingLocations = true);
    final res = await _controller.getLocations();
    setState(() => _isLoadingLocations = false);

    if (res['success'] ?? false) {
      final rawList = res['data'];
      final List parsed = rawList is List ? rawList : (rawList is Map ? rawList.values.toList() : []);
      setState(() {
        _locations = parsed.map((e) => _POOption.fromJson(e)).toList();
      });

      // If editing, re-select the saved location then reload its options
      if (prefillOrder != null && prefillOrder.location.isNotEmpty) {
        final q = prefillOrder.location.toLowerCase();

        // Match by id/tid first, then by exact label, then by partial label/name
        final match = _locations.where((l) =>
        l.id == prefillOrder.location ||
            l.label.toLowerCase() == q ||
            l.label.toLowerCase().contains(q)
        ).firstOrNull;
        if (match != null) {
          setState(() {
            _locationId    = match.id;
            _locationLabel = match.label;
          });
          await _fetchCascadingOptions(match.id, prefillOrder: prefillOrder);
        } else if (_locations.isNotEmpty) {
          // No match found — load first location's options but keep prefill values
          setState(() {
            _locationId    = _locations.first.id;
            _locationLabel = _locations.first.label;
          });
          await _fetchCascadingOptions(_locationId, prefillOrder: prefillOrder);
        }
      } else if (_locations.isNotEmpty) {
        final _POOption? carriedOver = widget.initialLocationId != null &&
            widget.initialLocationId!.isNotEmpty
            ? _locations
            .where((l) => l.id == widget.initialLocationId)
            .firstOrNull
            : null;
        final _POOption fallback = carriedOver ?? _locations.first;
        setState(() {
          _locationId = fallback.id;
          _locationLabel = fallback.label;
          if (carriedOver != null) {_locations = [carriedOver];}
        });
        _fetchCascadingOptions(_locationId);
      }
    }
  }

  Future<void> _fetchCascadingOptions(String locationId, {PurchaseOrder? prefillOrder}) async {
    setState(() => _isLoadingOptions = true);
    final res = await _controller.getPurchaseOptions(locationId: locationId);
    setState(() => _isLoadingOptions = false);

    if (!(res['success'] ?? false)) return;
    final data = res['data'] as Map<String, dynamic>? ?? {};

    setState(() {
      _POOption _parse(dynamic raw) => _POOption.fromJson(raw);

      if (data['currency'] is List) _currencies = (data['currency'] as List).map(_parse).toList();
      if (data['vendor'] is List) _vendors = (data['vendor'] as List).map(_parse).toList();
      if (data['urgency'] is List) _urgencies = (data['urgency'] as List).map(_parse).toList();
      if (data['mode'] is List) _modes = (data['mode'] as List).map(_parse).toList();
      if (data['trx'] is List) {
        _trxCodes = (data['trx'] as List).map(_parse).toList();
        // Resolve any pre-loaded trx items whose codeValue may be a readable name
        // (e.g. "Discount") rather than a tid — match and replace with the tid
        for (final trxItem in _trxItems) {
          if (trxItem.codeValue == null || trxItem.codeValue!.isEmpty) continue;
          final alreadyMatches = _trxCodes.any((t) => t.id == trxItem.codeValue);
          if (!alreadyMatches) {
            final q = trxItem.codeValue!.toLowerCase();
            final match = _trxCodes.where((t) =>
            //t.code.toLowerCase() == q ||
                t.name.toLowerCase() == q ||
                /*t.label.toLowerCase() == q ||
                t.label.toLowerCase().contains(q) ||*/
                q.contains(t.name.toLowerCase())
            ).firstOrNull;
            if (match != null) trxItem.codeValue = match.id;
          }
        }
      }
      if (data['uom'] is List) {
        _uomOptions = (data['uom'] as List)
            .map((e) => e is Map ? (e['code'] ?? e['name'] ?? e.toString()).toString() : e.toString())
            .where((s) => s.isNotEmpty)
            .toList();

        // Build a reverse map: uom id → display name, for resolving raw ids stored
        // in line items (e.g. UOM "1" from the detail API → "PCS" display name).
        final Map<String, String> uomIdToName = {
          for (final e in (data['uom'] as List))
            if (e is Map && e['id'] != null && e['name'] != null)
              e['id'].toString(): (e['code'] ?? e['name']).toString()
        };

        // Resolve each pre-loaded line item's uomValue from raw id to display name.
        for (final lineItem in _lineItems) {
          final raw = lineItem.uomValue;
          if (raw == null || raw.isEmpty) continue;
          // If raw is already a known display name, leave it alone.
          if (_uomOptions.contains(raw)) continue;
          // Try reverse id lookup first, then name/code match.
          final resolved = uomIdToName[raw]
              ?? _uomOptions.where((n) => n.toLowerCase() == raw.toLowerCase()).firstOrNull;
          if (resolved != null) {
            lineItem.uomValue = resolved;
            // Ensure the resolved name is also in per-item uomOptions list.
            if (!lineItem.uomOptions.contains(resolved)) {
              lineItem.uomOptions = [resolved];
            }
          }
        }
      }

      // bcurrency is nested inside data['loc'][0]['bcurrency'], not at top level
      final locList = data['loc'];
      final locObj = locList is List && locList.isNotEmpty
          ? locList.first as Map<String, dynamic>
          : <String, dynamic>{};
      _bcurrency = locObj['bcurrency']?.toString() ?? '';

      // Only use the API default rate for new orders.
      // For existing orders, the saved rate is restored below from prefillOrder.exchangeRate.
      if (prefillOrder == null) {
        _exchangeRate = double.tryParse(data['exrate']?.toString() ?? '1') ?? 1.0;
        _exRateCtrl.text = _exchangeRate.toString();
      }

      // Always resolve base currency — needed for exchange-rate row in both modes.
      _defaultCurrency = _currencies.where((c) => c.id == _bcurrency).firstOrNull ??
          (_currencies.isNotEmpty ? _currencies.first : null);

      if (data['ref_no'] != null) _refNoCtrl.text = data['ref_no'].toString();

      if (prefillOrder != null) {
        // ── View / edit mode ──────────────────────────────────────────────────
        // Do NOT auto-select the first item. Match by id → code → name → label.
        // If nothing matches leave the field null so the dropdown shows blank
        // instead of a wrong first option (old records may have no urgency/mode
        // data, and the detail API returns readable names not tids).
        _POOption? _match(List<_POOption> list, String val) {
          if (val.isEmpty) return null;
          final q = val.toLowerCase();
          return list.where((o) => o.id == val).firstOrNull
             /* ?? list.where((o) => o.code.toLowerCase() == q).firstOrNull
              ?? list.where((o) => o.name.toLowerCase() == q).firstOrNull
              ?? list.where((o) => o.label.toLowerCase() == q).firstOrNull*/
              ?? list.where((o) => o.name.toLowerCase().contains(q) || q.contains(o.name.toLowerCase())).firstOrNull;
              //?? list.where((o) => o.label.toLowerCase().contains(q) || q.contains(o.code.toLowerCase())).firstOrNull;
        }

        _selectedCurrency = _match(_currencies, prefillOrder.currency);
        _selectedUrgency  = _match(_urgencies,  prefillOrder.urgency);
        _selectedMode     = _match(_modes,       prefillOrder.mode);
        _selectedVendor   = _match(_vendors,     prefillOrder.vendor);

        // Restore ref no and exchange rate from the saved order
        if (prefillOrder.refNo.isNotEmpty) _refNoCtrl.text = prefillOrder.refNo;
        if (prefillOrder.exchangeRate > 0) {
          _exchangeRate = prefillOrder.exchangeRate;
          _exRateCtrl.text = _exchangeRate.toString();
        }
      } else {
        // ── Create mode ───────────────────────────────────────────────────────
        // Auto-select first item in each list as a sensible default.
        if (_currencies.isNotEmpty) _selectedCurrency = _defaultCurrency ?? _currencies.first;
        if (_urgencies.isNotEmpty)  _selectedUrgency  = _urgencies.first;
        if (_modes.isNotEmpty)      _selectedMode     = _modes.first;
        if (_vendors.isNotEmpty)    _selectedVendor   = _vendors.first;
      }
    });
  }

  void _addLineItem() => setState(() => _lineItems.add(_LineItemForm()));
  void _addTrxItem() => setState(() => _trxItems.add(_TrxLineItemForm()));

  void _toggleLineItemSaved(_LineItemForm item) {
    if (item.isSaved) {
      setState(() => item.isSaved = false);
      return;
    }

    final qtyText    = item.availableQtyCtrl.text.trim();
    final qty        = double.tryParse(qtyText);
    final qtyInvalid = qtyText.isEmpty || qty == null || qty <= 0;
    final uomInvalid = item.uomValue == null || item.uomValue!.trim().isEmpty;

    if (qtyInvalid || uomInvalid) {
      setState(() {
        item.qtyError = qtyInvalid;
        item.uomError = uomInvalid;
      });
      CommonUtils.showSnackBar(
        '${context.str.quantity} & ${context.str.uom} ${context.str.fieldRequired} ${context.str.qtyMustGreaterThanZero}',
        'danger',
        context,
      );
      return;
    }

    setState(() {
      item.qtyError = false;
      item.uomError = false;
      item.isSaved  = true;
    });
  }

  void _removeLineItem(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.str.delete),
        content: Text(ctx.str.confirmDeleteDescription),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.str.no)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.str.yes, style: TextStyle(color: AppTheme.danger(context))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _lineItems[index].dispose();
        _lineItems.removeAt(index);
      });
    }
  }

  void _removeTrxItem(int index) {
    setState(() {
      _trxItems[index].dispose();
      _trxItems.removeAt(index);
    });
  }

  Future<void> _triggerProductSearch(_LineItemForm item) async {
    if (_locationId.isEmpty) {
      CommonUtils.showSnackBar('${context.str.pleaseSelect} ${context.str.aLocationFirst}', 'danger', context);
      return;
    }

    final selectedProduct = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final searchCtrl = TextEditingController();
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx2, setModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(ctx2).size.height * 0.75,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: context.str.productName, floatingLabelStyle: const TextStyle(fontSize:18),
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (val) => setModal(() => searchQuery = val),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: searchQuery.isEmpty
                            ? Center(child: Text(context.str.typeToSearchProducts, style: const TextStyle(fontSize: 15)))
                            : FutureBuilder<Map<String, dynamic>>(
                          future: _controller.searchProducts(searchText: searchQuery),
                          builder: (ctx3, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final res = snapshot.data;
                            if (res == null || !(res['success'] ?? false)) {
                              return Center(child: Text(context.str.noProductsFound, style: const TextStyle(fontSize: 15)));
                            }
                            final list = res['data'] as List? ?? [];
                            if (list.isEmpty) return Center(child: Text(context.str.noProductsFound, style: const TextStyle(fontSize: 15)));
                            return ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (ctx4, i) {
                                final prod = list[i] as Map<String, dynamic>;
                                return ListTile(
                                  title: Text(prod['name']?.toString() ?? ''),
                                  subtitle: Text(prod['sku']?.toString() ?? ''),
                                  onTap: () => Navigator.pop(ctx2, prod),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedProduct == null || !mounted) return;

    final productId = selectedProduct['id']?.toString() ?? '';
    final productName = selectedProduct['name']?.toString() ??
        selectedProduct['product_name']?.toString() ?? '';

    setState(() {
      item.productCtrl.text = productName;
      item.productId = productId;
      item.isLoadingDetail = true;
      item.descriptionCtrl.text = '';
      item.availableQtyCtrl.text = '';
      item.uPriceCtrl.text = '';
      item.prDocOptions = [];
      item.prDocValue = null;
      // Reset balance fields — they're re-populated from the product detail
      // response below, or remain '0' if the API returns no values.
      item.poQtyCtrl.text = '0';
      item.prQtyCtrl.text = '0';
      item.stockQtyCtrl.text = '0';
    });

    final detailRes = await _controller.getProductDetail(
      productId: productId,
      locationId: _locationId,
    );

    if (!mounted) return;

    setState(() {
      item.isLoadingDetail = false;
      if (!(detailRes['success'] ?? false)) return;

      // API response: {"data": {"product": {...}, "pr_doc": [...], "uom_listing": [...]}}
      final d = detailRes['data'] as Map<String, dynamic>? ?? {};
      final product = d['product'] as Map<String, dynamic>? ?? {};

      // ──────────────── Core fields from product object ──────────────────────
      item.productId = product['id']?.toString() ?? product['product']?.toString() ?? '';
      item.did = product['did']?.toString() ?? '';
      item.variation = product['variation']?.toString() ?? '0';
      item.descriptionCtrl.text = product['name']?.toString() ?? '';
      item.uPriceCtrl.text = (product['uprice'] ?? product['ucost'] ?? '0').toString();

      // ───────────── PO Qty / PR Qty / Stock — read-only balance fields ───────
      // os_bal -> PO Qty, pr_qty -> PR Qty, available -> Stock.
      // Fall back to '0' if the API doesn't return a value for the product.
      item.poQtyCtrl.text = _formatQty(product['os_bal']);
      item.prQtyCtrl.text = _formatQty(product['pr_qty']);
      item.stockQtyCtrl.text = _formatQty(product['available']);

      // ──────────────────── UOM — from uom_listing array ──────────────────────
      final rawUomList = d['uom_listing'];
      if (rawUomList is List && rawUomList.isNotEmpty) {
        item.uomOptions = rawUomList
            .map((e) => e is Map ? (e['name'] ?? e['code'] ?? e.toString()).toString() : e.toString())
            .where((s) => s.isNotEmpty)
            .toList();
        // Store the uom id map so we can send the correct id on submit
        item.uomIdMap = {
          for (final e in rawUomList)
            if (e is Map && e['name'] != null) e['name'].toString(): e['id']?.toString() ?? ''
        };
      } else {
        item.uomOptions = _uomOptions;
        item.uomIdMap = {};
      }
      item.uomValue = item.uomOptions.isNotEmpty ? item.uomOptions.first : null;

      // ─────────────────── PR Doc — from pr_doc array ─────────────────────────
      final rawDocs = d['pr_doc'];
      if (rawDocs is List && rawDocs.isNotEmpty) {
        item.prDocList = List<Map<String, dynamic>>.from(
            rawDocs.map((e) => e is Map ? Map<String, dynamic>.from(e) : {}));
        item.prDocOptions = item.prDocList
            .map((e) => e['disp']?.toString() ?? e['doc']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        item.prDocValue = item.prDocOptions.isNotEmpty ? item.prDocOptions.first : null;
      } else {
        item.prDocList = [];
        item.prDocOptions = [];
        item.prDocValue = null;
      }
    });
  }

  /// Formats a raw numeric balance value (e.g. "0.000", "12.500") from the
  /// product detail API into a clean display string. Falls back to '0' for
  /// null/empty/unparsable values.
  String _formatQty(dynamic raw) {
    final parsed = double.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '0';
    return parsed == parsed.truncate() ? parsed.toInt().toString() : parsed.toString();
  }

  double _calculateGrossTotal() {
    final itemsTotal = _lineItems.fold(0.0, (sum, item) {
      final qty = double.tryParse(item.availableQtyCtrl.text) ?? 0;
      final price = double.tryParse(item.uPriceCtrl.text) ?? 0;
      return sum + (qty * price);
    });

    final trxTotal = _trxItems.fold(0.0, (sum, item) {
      final amt = double.tryParse(item.amountCtrl.text) ?? 0.0;

      // Look up the actual option object to check its label/code
     final selectedOpt = _trxCodes.where((t) => t.id == item.codeValue).firstOrNull;
      final isDeduction = selectedOpt?.isDeduction ?? false;
      if (isDeduction) {
        return sum - amt; // Deduct from total amount
      } else {
        return sum + amt; // Addition logic for FREIGHT CHARGE
      }
    });

    return itemsTotal + trxTotal;
  }

  void _handleSave() async {
    final unsavedIndex = _lineItems.indexWhere((item) => !item.isSaved);
    if (unsavedIndex != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.str.save} ${context.str.item} #${unsavedIndex + 1} ${context.str.fieldRequired}'),
          backgroundColor: AppTheme.danger(context),
        ),
      );
      return;
    }

    final vendorBlank  = _selectedVendor == null;
    final urgencyBlank = _selectedUrgency == null;
    if (vendorBlank || urgencyBlank) {
      setState(() {
        _vendorError  = vendorBlank;
        _urgencyError = urgencyBlank;
      });
      CommonUtils.showSnackBar(
        '${context.str.vendor} & ${context.str.urgency} ${context.str.fieldRequired}',
        'danger',
        context,
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      final total = _calculateGrossTotal();

      final newOrder = PurchaseOrder(
        id: widget.order?.id ?? '',
        docNo: widget.order?.docNo ?? 'NEW-${DateTime.now().millisecondsSinceEpoch}',
        poDate: _poDate,
        docDate: DateTime.now(),
        location: _locationId,
        vendor: _selectedVendor?.id ?? '',
        refNo: _refNoCtrl.text,
        currency: _selectedCurrency?.id ?? '',
        urgency: _selectedUrgency?.id ?? '',
        mode: _selectedMode?.id ?? '',
        expectedReceiptDate: _expectedReceiptDate,
        remark: _remarkCtrl.text,
        totalAmount: total,
        status: widget.order?.status ?? 'Draft',
        createdOn: widget.order?.createdOn ?? DateTime.now(),
        lineItems: _lineItems
            .where((item) => item.productCtrl.text.trim().isNotEmpty)
            .map((item) {
          final qty = double.tryParse(item.availableQtyCtrl.text) ?? 0;
          final price = double.tryParse(item.uPriceCtrl.text) ?? 0;
          return POLineItem(
            productNameCodeSku: item.productCtrl.text,
            productId: item.productId,
            variation: item.variation,
            did: item.did,
            refHid: item.refHid,
            refDid: item.refDid,
            description: item.descriptionCtrl.text,
            prDoc: item.refDoc.isNotEmpty ? item.refDoc : (item.prDocValue ?? ''),
            poQty: double.tryParse(item.poQtyCtrl.text)?.toInt() ?? 0,
            prQty: double.tryParse(item.prQtyCtrl.text)?.toInt() ?? 0,
            stockQty: double.tryParse(item.stockQtyCtrl.text)?.toInt() ?? 0,
            availableQty: qty.toInt(),
            uom: item.uomIdMap[item.uomValue] ?? item.uomValue ?? '',
            uPrice: price,
            amount: qty * price,
            remark: item.remarkCtrl.text,
          );
        }).toList(),
        trxItems: _trxItems.map((item) => POTrxLineItem(
          code: item.codeValue ?? '',
          amount: double.tryParse(item.amountCtrl.text) ?? 0.0,
          remark: item.remarkCtrl.text,
        )).toList(),
      );

      try {
        await _controller.savePurchaseOrder(
          context: context,
          order: newOrder,
          isUpdate: widget.order != null,
          bcurrency: _bcurrency,
          exchangeRate: _exchangeRate,
          onSuccess: (savedOrder) {
            // No need to reset state here as we are popping the screen anyway
            widget.onSave(savedOrder);
            Navigator.pop(context);
          },
        );
      } catch (e) {
        // 2. Fallback: If the API throws an unexpected exception, turn off the loader
        setState(() => _isSaving = false);
      }
    } else {
      CommonUtils.showSnackBar(context.str.fieldRequired, 'danger', context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // When viewing an existing order, the entire form is read-only.
    // No editing, no cancel, no create/save actions are available.
    final bool isViewOnly = widget.order != null;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(isViewOnly ? (widget.order?.docNo ?? context.str.purchaseOrder) : context.str.purchaseOrder, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: _isLoadingLocations
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeaderCard(isViewOnly: isViewOnly),
                    const SizedBox(height: 20),
                    _buildItemSectionHeader(isViewOnly: isViewOnly),
                    ..._lineItems.asMap().entries.map((e) => _buildVerticalItemCard(e.key, e.value, isViewOnly: isViewOnly)),
                    if (!isViewOnly && _lineItems.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _addLineItem,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: AppTheme.primary(context), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(
                          '${context.str.add} ${context.str.item}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (!isViewOnly || _trxItems.isNotEmpty) ...[
                      _buildTrxSectionHeader(isViewOnly: isViewOnly),
                      ..._trxItems.asMap().entries.map((e) => _buildTrxLineItemCard(e.key, e.value, isViewOnly: isViewOnly)),
                    ],
                    if (!isViewOnly) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                          onPressed: _addTrxItem,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: BorderSide(color: AppTheme.primary(context), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.add, size: 20),
                          label: Text('${context.str.add} ${context.str.trxCode}', style: const TextStyle(fontWeight: FontWeight.bold))
                      ),
                    ],
                    _buildApprovalLogSection(isViewOnly: isViewOnly),
                  ],
                ),
              ),
              _buildStickyFooter(isViewOnly: isViewOnly),
            ],
          ),
        )
      ),
    );
  }

  Widget _buildHeaderCard({required bool isViewOnly}) {
    // Show rate row when selected currency differs from the location's base currency
    final bool showConversionRow = _selectedCurrency != null &&
        _defaultCurrency != null &&
        _selectedCurrency!.id != _defaultCurrency!.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Location
            DropdownButtonFormField<_POOption>(
              isExpanded: true,
              initialValue: _locations.where((l) => l.id == _locationId).firstOrNull,
              decoration: InputDecoration(
                labelText: context.str.location,
                labelStyle: TextStyle(fontSize: 19, color: AppTheme.textPrimary(context)),
                prefixIcon: Icon(Icons.location_on, color: AppTheme.primary(context)),
                isDense: true,
              ),
              items: _locations.map((loc) => DropdownMenuItem(
                value: loc,
                child: Text(loc.label, style: TextStyle(color: AppTheme.textPrimary(context))),
              )).toList(),
              // Disabled in view-only mode
              onChanged: isViewOnly ? null : (val) {
                if (val != null) {
                  setState(() {
                    _locationId = val.id;
                    _locationLabel = val.label;
                    _selectedVendor = null;
                    _selectedCurrency = null;
                    _selectedUrgency = null;
                    _selectedMode = null;
                    _vendorError = false;
                    _urgencyError = false;
                    // If the selected location has no id (blank), wipe all location is not left behind in the dropdowns.
                    if (val.id.isEmpty) {
                      _vendors = [];
                      _currencies = [];
                      _urgencies = [];
                      _modes = [];
                      _trxCodes = [];
                      _uomOptions = [];
                    }
                  });
                  _fetchCascadingOptions(val.id);
                }
              },
            ),
            const Divider(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.primary(context)),
                    const SizedBox(width: 8),
                    Text('PO ${context.str.date}', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary(context))),
                  ],
                ),
                // Disabled in view-only mode — pass null callback so date picker never opens
                _buildDateField(_poDate, isViewOnly ? null : (d) => setState(() => _poDate = d)),
              ],
            ),
            const Divider(height: 14),
            if (_isLoadingOptions) const LinearProgressIndicator(),
            // Vendor + Currency
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<_POOption>(
                    initialValue: _selectedVendor,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.str.vendor, isDense: true, labelStyle: TextStyle(fontSize: 19, color: _vendorError ? AppTheme.danger(context) : AppTheme.textPrimary(context)),
                    enabledBorder: _vendorError ? UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.danger(context))) : null,
                    focusedBorder: _vendorError ? UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.danger(context))) : null,
                    ),
                    items: _vendors.map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(v.name, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: AppTheme.textPrimary(context))),
                    )).toList(),
                    onChanged: isViewOnly ? null : (val) => setState(() {_selectedVendor = val; _vendorError = false;})
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<_POOption>(
                    initialValue: _selectedCurrency,
                    decoration: InputDecoration(labelText: context.str.currency, isDense: true, labelStyle: TextStyle(fontSize: 19, color: AppTheme.textPrimary(context))),
                    items: _currencies.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.code.isNotEmpty ? c.code : c.label, style: TextStyle(color:AppTheme.textPrimary(context))),
                    )).toList(),
                    onChanged: isViewOnly ? null : (val) => setState(() => _selectedCurrency = val),
                  ),
                ),
              ],
            ),
            // Exchange rate row
            if (showConversionRow) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary(context).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primary(context).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.currency_exchange, size: 16, color: AppTheme.primary(context)),
                    const SizedBox(width: 8),
                    Text(
                      'Rate: 1 ${_selectedCurrency!.code.isNotEmpty ? _selectedCurrency!.code : _selectedCurrency!.label} = ',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _exRateCtrl,
                        readOnly: isViewOnly,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: InputBorder.none,
                          suffixText: _defaultCurrency?.code.isNotEmpty == true ? _defaultCurrency!.code : (_defaultCurrency?.label ?? ''),
                          suffixStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        onChanged: isViewOnly ? null : (_) => setState(() {
                          _exchangeRate = double.tryParse(_exRateCtrl.text) ?? 1.0;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Urgency + Mode
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_POOption>(
                    initialValue: _selectedUrgency,
                    decoration: InputDecoration(labelText: context.str.urgency, isDense: true, labelStyle: TextStyle(fontSize: 19, color: _urgencyError ? AppTheme.danger(context) : AppTheme.textPrimary(context)),
                      enabledBorder: _urgencyError ? UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.danger(context))) : null,
                      focusedBorder: _urgencyError ? UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.danger(context))) : null,
                    ),
                    hint: Text(context.str.select, style: const TextStyle(fontSize: 13)),
                    items: _urgencies.map((u) => DropdownMenuItem(value: u, child: Text(u.name, style: TextStyle(color: AppTheme.textPrimary(context))))).toList(),
                    onChanged: isViewOnly ? null : (val) => setState(() {_selectedUrgency = val; _urgencyError = false;})
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<_POOption>(
                    initialValue: _selectedMode,
                    decoration: InputDecoration(labelText: context.str.mode, isDense: true, labelStyle: TextStyle(fontSize: 19, color: AppTheme.textPrimary(context))),
                    hint: Text(context.str.select, style: const TextStyle(fontSize: 13)),
                    items: _modes.map((m) => DropdownMenuItem(value: m, child: Text(m.name, style: TextStyle(color: AppTheme.textPrimary(context))))).toList(),
                    onChanged: isViewOnly ? null : (val) => setState(() => _selectedMode = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_available, size: 16, color: AppTheme.primary(context)),
                    const SizedBox(width: 8),
                    Text(context.str.expectedReceiptDate, style: const TextStyle(fontSize: 14)),
                  ],
                ),
                // Disabled in view-only mode
                _buildDateField(_expectedReceiptDate, isViewOnly ? null : (picked) => setState(() => _expectedReceiptDate = picked)),
              ],
            ),
            ExpansionTile(
              title: Text(context.str.moreInputs, style: TextStyle(fontSize: 16, color: AppTheme.primary(context), fontWeight: FontWeight.w600)),
              tilePadding: EdgeInsets.zero,
              children: [
                _buildTextField(_refNoCtrl, context.str.refNo, readOnly: isViewOnly),
                const SizedBox(height: 12),
                _buildTextField(_remarkCtrl, context.str.remark, readOnly: isViewOnly),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemSectionHeader({required bool isViewOnly}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(context.str.item, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
      ],
    );
  }

  Widget _buildVerticalItemCard(int idx, _LineItemForm item, {required bool isViewOnly}) {
    final qty = double.tryParse(item.availableQtyCtrl.text) ?? 0;
    final price = double.tryParse(item.uPriceCtrl.text) ?? 0;
    final itemAmount = qty * price;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        // No active-edit border highlight in view-only mode
        side: BorderSide(
          color: isViewOnly
              ? Colors.transparent
              : (item.isSaved ? Colors.transparent : AppTheme.primary(context).withValues(alpha: 0.5)),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primary(context).withValues(alpha: 0.15),
                  child: Text('${idx + 1}', style: TextStyle(fontSize: 10, color: AppTheme.primary(context), fontWeight: FontWeight.bold)),
                ),
                // Save and delete action icons hidden in view-only mode
                if (!isViewOnly)
                  Row(
                    children: [
                      _iconBtn(
                          item.isSaved ? Icons.check_circle : Icons.save_outlined,
                          item.isSaved ? Colors.green : AppTheme.primary(context),
                              () => _toggleLineItemSaved(item)),
                      const SizedBox(width: 8),
                      _iconBtn(Icons.delete_outline, AppTheme.danger(context), () => _removeLineItem(idx)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (item.isLoadingDetail)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            // In view-only mode all fields are locked — no pointer events, full opacity
            IgnorePointer(
              ignoring: isViewOnly || item.isSaved || item.isLoadingDetail,
              child: Opacity(
                opacity: (isViewOnly || item.isSaved || item.isLoadingDetail) ? 1.0 : 1.0,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: isViewOnly ? null : () => _triggerProductSearch(item),
                      child: AbsorbPointer(
                        child: _buildItemField(item.productCtrl, context.str.productName),
                      ),
                    ),
                    _buildItemField(item.descriptionCtrl, context.str.description),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _buildReadOnlyItemField(item.poQtyCtrl, context.str.POQty)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildReadOnlyItemField(item.prQtyCtrl, context.str.PRQty)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildReadOnlyItemField(item.stockQtyCtrl, context.str.stock)),
                      ],
                    ),
                    _buildPrDocDropdown(item),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildItemField(item.availableQtyCtrl, context.str.quantity, isNum: true, hasError: item.qtyError, onChangedExtra: () => item.qtyError = false)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildItemDropdown(item, hasError: item.uomError)),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildItemField(item.uPriceCtrl, context.str.unitPrice, isNum: true)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              key: ValueKey(itemAmount),
                              initialValue: itemAmount.toStringAsFixed(2),
                              readOnly: true,
                              enabled: false,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary(context),
                                fontSize: 16,
                              ),
                              decoration:  InputDecoration(
                                labelText: context.str.amount,
                                labelStyle: TextStyle(color: AppTheme.textPrimary(context)),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                                border: const OutlineInputBorder(),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppTheme.border(context)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _buildItemField(item.remarkCtrl, context.str.remark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrxSectionHeader({required bool isViewOnly}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(context.str.trxCode, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
      ],
    );
  }

  Widget _buildTrxLineItemCard(int idx, _TrxLineItemForm item, {required bool isViewOnly}) {
    final selectedOpt = _trxCodes.where((t) => t.id == item.codeValue).firstOrNull;
    final isDeduction = selectedOpt?.isDeduction ?? false;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _trxCodes.any((t) => t.id == item.codeValue)
                        ? item.codeValue
                        : null,
                    decoration: InputDecoration(labelText: context.str.trxCode, isDense: true, border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    labelStyle: TextStyle(color: AppTheme.textPrimary(context)),
                    floatingLabelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))
                    ),
                    selectedItemBuilder: (context) => _trxCodes.map((t) =>
                        Text(t.label, style: TextStyle(color: AppTheme.textPrimary(context))),
                    ).toList(),
                    items: _trxCodes.map((t) => DropdownMenuItem(value: t.id, child: Text(t.label, ))).toList(),
                    // Disabled in view-only mode
                    onChanged: isViewOnly ? null : (v) => setState(() => item.codeValue = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: item.amountCtrl,
                    readOnly: isViewOnly,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    focusNode: isViewOnly ? FocusNode(canRequestFocus: false) : null,
                    decoration: InputDecoration(
                      labelText: context.str.amount,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      focusedBorder: isViewOnly ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)) : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      labelStyle: TextStyle(color: AppTheme.textPrimary(context)),
                      floatingLabelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context)),
                      prefix: isDeduction ? const Text('- ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)) : const SizedBox(width: 12, height: 20)
                    ),
                    onChanged: isViewOnly ? null : (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.remarkCtrl,
                    readOnly: isViewOnly,
                    focusNode: isViewOnly ? FocusNode(canRequestFocus: false) : null,
                    decoration: InputDecoration(labelText: context.str.remark, isDense: true, border: const OutlineInputBorder(),
                    focusedBorder: isViewOnly ? const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)) : null,
                    labelStyle: TextStyle(color: AppTheme.textPrimary(context)),
                    floatingLabelStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))
                    ),
                    onChanged: isViewOnly ? null : (_) => setState(() {}),
                  ),
                ),
                // Delete button hidden in view-only mode
                if (!isViewOnly) ...[
                  const SizedBox(width: 12),
                  _iconRemoveBtn(Colors.grey.shade400, () => _removeTrxItem(idx)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // View-only: tap-to-expand Approval Log, shown under the TRX section.
  // Renders nothing in create mode or when the order has no log entries.
  Widget _buildApprovalLogSection({required bool isViewOnly}) {
    final logs = widget.order?.approvalLogs ?? const <POApprovalLog>[];
    if (!isViewOnly || logs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        InkWell(
          onTap: () => setState(() => _approvalLogExpanded = !_approvalLogExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.str.approvalLog,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                AnimatedRotation(
                  turns: _approvalLogExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down, color: AppTheme.primary(context)),
                ),
              ],
            ),
          ),
        ),

        // Animated Container Box holding the entries
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border(context).withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: logs.asMap().entries.map((e) {
                final idx = e.key;
                return Container(
                  // Add a divider between list entries, but skip the very first top border
                  decoration: BoxDecoration(
                    border: idx == 0
                        ? null
                        : Border(top: BorderSide(color: AppTheme.border(context))),
                  ),
                  child: _buildApprovalLogEntry(
                    no: idx + 1,
                    log: e.value,
                    isLast: idx == logs.length - 1,
                  ),
                );
              }).toList(),
            ),
          ),
          crossFadeState: _approvalLogExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }

  Widget _buildApprovalLogEntry({required int no, required POApprovalLog log, required bool isLast}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(width: 90, child: _approvalLogField(label: context.str.numCode, value: no.toString())),
                    if (log.action.isNotEmpty) _buildActionBadge(log.action),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _approvalLogField(label: context.str.actionBy, value: log.actionBy),
              const SizedBox(height: 14),
              _approvalLogField(label: context.str.actionDate, value: log.actionDate),
              const SizedBox(height: 14),
              _approvalLogField(label: context.str.remark, value: log.remark, minLines: 2),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: AppTheme.border(context)),
      ],
    );
  }

  // A read-only field styled like the rest of the form's inputs (outlined box, floating label) rather than a plain "label: value" table row.
  Widget _approvalLogField({required String label, required String value, int minLines = 1}) {
    const borderColor = Colors.grey;
    final disabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: borderColor),
    );
    return TextFormField(
      initialValue: value,
      readOnly: true,
      enabled: false,
      minLines: minLines,
      maxLines: minLines > 1 ? minLines + 2 : 1,
      style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: AppTheme.textPrimary(context)),
        floatingLabelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary(context)
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: disabledBorder,
        enabledBorder: disabledBorder,
        disabledBorder: disabledBorder,
        focusedBorder: disabledBorder,
      ),
    );
  }

  Widget _buildActionBadge(String action) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: AppTheme.actionLogColor(action, context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        action,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  String get _currencyPrefix {
    final code = _selectedCurrency?.code.isNotEmpty == true ? _selectedCurrency!.code : (_selectedCurrency?.label ?? '');
    return code.isNotEmpty ? '$code ' : '';
  }

  Widget _buildStickyFooter({required bool isViewOnly}) {
    final finalTotal = _calculateGrossTotal();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: isViewOnly
      // View-only: show total amount only — no action buttons
          ? Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.str.totalAmount.toUpperCase(),
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context))),
                Text('$_currencyPrefix${finalTotal.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.primary(context))),
              ],
            ),
          ),
        ],
      )
      // Create mode: total + CREATE button
          : Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.str.totalAmount.toUpperCase(),
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context))),
                Text('$_currencyPrefix${finalTotal.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.primary(context))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null :_handleSave,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24)),
              child: _isSaving
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : Text(context.str.create.toUpperCase()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, {bool required = false, int maxLines = 1, bool readOnly = false}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      readOnly: readOnly,
      enabled: !readOnly,
      style: readOnly ? TextStyle(color: AppTheme.textPrimary(context), overflow: TextOverflow.ellipsis) : null,
      decoration: InputDecoration(labelText: label, isDense: true, labelStyle: TextStyle(fontSize: 18, color: AppTheme.textPrimary(context))),
      validator: (required && !readOnly) ? (v) => v!.isEmpty ? context.str.fieldRequired : null : null,
    );
  }

  Widget _buildItemField(TextEditingController ctrl, String label, {bool isNum = false, bool hasError = false, VoidCallback? onChangedExtra}) {
    final errorBorder = OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger(context)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        onChanged: (_) => setState(() => onChangedExtra?.call()),
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(),
        enabledBorder: hasError ? errorBorder : null,
        focusedBorder: hasError ? errorBorder : null,
        labelStyle: TextStyle(color: hasError ? AppTheme.danger(context) : AppTheme.textPrimary(context)),
        floatingLabelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: hasError ? AppTheme.danger(context) : AppTheme.textPrimary(context)),
        ),
      ),
    );
  }

  /// Read-only display field — used for PO Qty / PR Qty / Stock, which are
  /// informational balances populated from the product detail API and are
  /// never directly editable by the user.
  Widget _buildReadOnlyItemField(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        readOnly: true,
        enabled: false,
        style: TextStyle(color: AppTheme.textPrimary(context)),
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(),
        floatingLabelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))
        ),
      ),
    );
  }

  Widget _buildItemDropdown(_LineItemForm item, {bool hasError = false}) {
    final opts = item.uomOptions.isNotEmpty ? item.uomOptions : _uomOptions;
    // Resolve uomValue: it may be a raw id (e.g. "1") rather than a display name.
    // Try reverse-lookup via uomIdMap (name→id reversed), then plain contains check.
    String? resolvedValue = item.uomValue;
    if (resolvedValue != null && !opts.contains(resolvedValue)) {
      // uomIdMap is name→id; reverse it to id→name for resolution.
      final reverseMap = item.uomIdMap.map((name, id) => MapEntry(id, name));
      resolvedValue = reverseMap[resolvedValue]
          ?? opts.where((n) => n.toLowerCase() == resolvedValue!.toLowerCase()).firstOrNull;
    }
    final val = resolvedValue != null && opts.contains(resolvedValue)
        ? resolvedValue
        : (opts.isNotEmpty ? opts.first : null);
    final errorBorder = OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger(context)));
    return DropdownButtonFormField<String>(
      initialValue: val,
      decoration: InputDecoration(labelText: context.str.uom, isDense: true, border: const OutlineInputBorder(),
      enabledBorder: hasError ? errorBorder : null,
      focusedBorder: hasError ? errorBorder : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      floatingLabelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: hasError ? AppTheme.danger(context) : AppTheme.textPrimary(context))),
      items: opts.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
      onChanged: (v) => setState(() {item.uomValue = v;
      item.uomError = false;})
    );
  }

  Widget _buildPrDocDropdown(_LineItemForm item) {
    final opts = item.prDocOptions;
    final val = item.prDocValue != null && opts.contains(item.prDocValue)
        ? item.prDocValue
        : (opts.isNotEmpty ? opts.first : null);
    return DropdownButtonFormField<String>(
      initialValue: val,
      decoration: InputDecoration(
        labelText: 'PR ${context.str.document}',
        isDense: true,
        border: const OutlineInputBorder(),
        labelStyle: TextStyle(color: AppTheme.textPrimary(context)),
        floatingLabelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context))
      ),
      items: opts.map((doc) {
        // Show doc + qty in the dropdown for clarity
        final docObj = item.prDocList.where((e) => (e['disp'] ?? e['doc'])?.toString() == doc).firstOrNull;
        final label = doc;
        return DropdownMenuItem(value: doc, child: Text(label, overflow: TextOverflow.ellipsis));
      }).toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          item.prDocValue = v;
          // Auto-fill ref fields and qty from the selected PR doc
          final docObj = item.prDocList.where((e) => (e['disp'] ?? e['doc'])?.toString() == v).firstOrNull;
          if (docObj != null) {
            item.refHid = docObj['hid']?.toString() ?? '';
            item.refDid = docObj['id']?.toString() ?? '';
            item.refDoc = docObj['doc']?.toString() ?? '';
            final docQty = double.tryParse(docObj['bal_qty']?.toString() ?? docObj['qty']?.toString() ?? docObj['balance']?.toString() ?? '') ?? 0;
            if (docQty != 0) {
              item.availableQtyCtrl.text = _formatQty(docQty.toString());
            }
            final prQty = double.tryParse(docObj['pr_qty']?.toString() ?? '') ?? 0;
            if (prQty != 0) {
              item.prQtyCtrl.text = _formatQty(prQty.toString());
            }
            // Also prefill price if the doc carries one
            final docPrice = double.tryParse(docObj['uprice']?.toString() ?? '') ?? 0;
            if (docPrice != 0) {
              item.uPriceCtrl.text = docPrice.toStringAsFixed(2);
            }
          }
        });
      },
    );
  }

  // onPicked is nullable — pass null to make the date field non-interactive (view-only)
  Widget _buildDateField(DateTime d, ValueChanged<DateTime>? onPicked) {
    return GestureDetector(
      onTap: onPicked == null ? null : () async {
        final picked = await showDatePicker(
            context: context, initialDate: d, firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (picked != null) onPicked(picked);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${d.day}/${d.month}/${d.year}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData i, Color c, VoidCallback t) => GestureDetector(
    onTap: t,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Icon(i, size: 18, color: c),
    ),
  );


  Widget _iconRemoveBtn(Color c, VoidCallback t) => GestureDetector(
    onTap: t,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
      child: const Icon(Icons.remove_rounded, size: 16, color: Colors.red),
    ),
  );
}

class _LineItemForm {
  final TextEditingController productCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();
  final TextEditingController availableQtyCtrl = TextEditingController();
  final TextEditingController uPriceCtrl = TextEditingController();
  final TextEditingController remarkCtrl = TextEditingController();
  // Read-only balance fields — populated from the product detail API
  // (os_bal -> poQty, pr_qty -> prQty, available -> stockQty).
  final TextEditingController poQtyCtrl = TextEditingController(text: '0');
  final TextEditingController prQtyCtrl = TextEditingController(text: '0');
  final TextEditingController stockQtyCtrl = TextEditingController(text: '0');
  String? uomValue;
  String? prDocValue;
  List<String> uomOptions = []; // populated from product detail API
  List<String> prDocOptions = []; // populated from product detail API
  Map<String, String> uomIdMap = {}; // uom name -> uom id for submission
  List<Map<String, dynamic>> prDocList = []; // full pr_doc objects for qty prefill
  bool isSaved = false;
  bool isLoadingDetail = false;
  bool qtyError = false;
  bool uomError = false;

  // API fields needed for submission
  String productId = '';
  String variation = '';
  String did = '';
  String refHid = '';
  String refDid = '';
  String refDoc = '';

  void dispose() {
    productCtrl.dispose();
    descriptionCtrl.dispose();
    availableQtyCtrl.dispose();
    uPriceCtrl.dispose();
    remarkCtrl.dispose();
    poQtyCtrl.dispose();
    prQtyCtrl.dispose();
    stockQtyCtrl.dispose();
  }

  static _LineItemForm fromItem(POLineItem item) {
    final f = _LineItemForm();
    f.productCtrl.text = item.productNameCodeSku;
    f.descriptionCtrl.text = item.description;

    // Prefer availableQty (qty field), then fall back to poQty (po_qty field).
    // Both can legitimately be 0 for a brand-new draft, so only use poQty when
    // availableQty is exactly 0 to avoid masking a genuine zero entry.
    final qty = item.availableQty > 0
        ? item.availableQty
        : (item.poQty > 0 ? item.poQty : 0);
    f.availableQtyCtrl.text = qty > 0 ? qty.toString() : '';

    f.uPriceCtrl.text = item.uPrice > 0 ? item.uPrice.toString() : '';
    f.remarkCtrl.text = item.remark;
    f.poQtyCtrl.text = item.poQty.toString();
    f.prQtyCtrl.text = item.prQty.toString();
    f.stockQtyCtrl.text = item.stockQty.toString();
    f.uomValue = item.uom.isNotEmpty ? item.uom : null;
    f.uomOptions = item.uom.isNotEmpty ? [item.uom] : [];
    f.uomIdMap = {};
    f.prDocValue = item.prDoc.isNotEmpty ? item.prDoc : null;
    f.prDocOptions = item.prDoc.isNotEmpty ? [item.prDoc] : [];
    f.prDocList = [];
    f.productId = item.productId;
    f.variation = item.variation;
    f.did = item.did;
    f.refHid = item.refHid;
    f.refDid = item.refDid;
    // isSaved = false so restored items are editable when the form opens.
    // The user taps the lock/check icon to mark them saved when done reviewing.
    f.isSaved = false;
    return f;
  }
}

/// Holds one API option entry — id/tid for submission, code+label for display.
class _POOption {
  final String id;    // tid / id from API — sent on submit
  final String code;  // short code e.g. 'USD', 'ABC'
  final String label; // full display name (m_name or name)
  final String name;  // plain 'name' field — used for fallback matching
  final String plusMinus;

  const _POOption({required this.id, required this.code, required this.label, this.name = '', this.plusMinus = '1'});

  factory _POOption.fromJson(dynamic raw) {
    if (raw is! Map) return _POOption(id: raw.toString(), code: '', label: raw.toString());
    final id    = raw['tid']?.toString() ?? raw['id']?.toString() ?? '';
    final code  = raw['code']?.toString() ?? '';
    final name  = raw['name']?.toString() ?? '';
    // Prefer m_name for display (e.g. "USD - US DOLLAR"), fallback to name
    final label = raw['m_name']?.toString() ?? (name.isNotEmpty ? name : (raw['label']?.toString() ?? code));
    final plusMinus = raw['plus_minus']?.toString() ?? '1';
    return _POOption(id: id, code: code, label: label, name: name, plusMinus: plusMinus);
  }

  bool get isDeduction => plusMinus == '-1';

  @override
  bool operator ==(Object other) => other is _POOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class _TrxLineItemForm {
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController remarkCtrl = TextEditingController();
  String? codeValue;

  void dispose() {
    amountCtrl.dispose();
    remarkCtrl.dispose();
  }

  static _TrxLineItemForm fromItem(POTrxLineItem item) {
    final f = _TrxLineItemForm();
    f.codeValue = item.code;
    f.amountCtrl.text = item.amount.toString();
    f.remarkCtrl.text = item.remark ?? '';
    return f;
  }
}