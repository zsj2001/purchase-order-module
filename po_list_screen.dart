import 'package:flutter/material.dart';
import 'package:base_template/module/purchase_order/po_model.dart';
import 'package:base_template/module/purchase_order/theme.dart';
import '../../extension/context_extension.dart';
import '../../common/localization/app_localization.dart';
import 'po_form_screen.dart';
import 'po_controller.dart';
import 'package:base_template/common/utils/common_api.dart';
import 'package:base_template/common/utils/common_utils.dart';

class POListScreen extends StatefulWidget {
  const POListScreen({super.key});

  @override
  State<POListScreen> createState() => _POListScreenState();
}

class _POListScreenState extends State<POListScreen> {
  final POController _controller = POController();

  // Loading flags
  bool _isLoadingLocations = false;
  bool _isLoading = false;

  // Location State
  List<Map<String, dynamic>> _locations = [];
  Map<String, dynamic>? _selectedLocation;

  // Status filter state (loaded from API)
  List<Map<String, dynamic>> _poStatuses = [];
  Map<String, dynamic>? _selectedStatus; // null = All

  // Data State
  List<PurchaseOrder> _orders = [];

  // Filter UI State
  bool _isFilterOpen = false;
  // Vendor dropdown
  List<Map<String, dynamic>> _vendors = [];
  Map<String, dynamic>? _selectedVendor;
  // Text filters
  final TextEditingController _docNoController = TextEditingController();
  // Product filter — stores selected product id (sent to API) and display name
  String _filterProductId   = '';
  String _filterProductName = '';
  final TextEditingController _refDocnoController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _itemRemarkController = TextEditingController();
  // Date range
  DateTime? _startDate;
  DateTime? _endDate;

  // Pagination State
  static const int _pageSize = 30;
  int _currentPage = 1;
  int _skip = 0;
  int _totalRecords = 0;

  @override
  void initState() {
    super.initState();
    _fetchLocations();
    _fetchPoStatuses();
    _fetchVendors();
  }

  @override
  void dispose() {
    _docNoController.dispose();
    _refDocnoController.dispose();
    _remarkController.dispose();
    _itemRemarkController.dispose();
    super.dispose();
  }

  // ──────────────── Step 1: load locations ──────────────────────────────────
  Future<void> _fetchLocations() async {
    setState(() => _isLoadingLocations = true);
    try {
      final res = await _controller.getLocations();
      if (res['success'] == true && res['data'] is List) {
        final list = (res['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _locations = list;
          if (list.isNotEmpty) {
            _selectedLocation = list.first;
          }
        });
        if (_selectedLocation != null) _fetchOrders();
      }
    } catch (e) {
    } finally {
      setState(() => _isLoadingLocations = false);
    }
  }

  Future<void> _fetchPoStatuses() async {
    try {
      final res = await _controller.getPoStatuses();
      if (res['success'] == true && res['data'] is List) {
        setState(() {
          _poStatuses = (res['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
    }
  }

  Future<void> _fetchVendors() async {
    try {
      final res = await _controller.getVendors();
      if (res['success'] == true && res['data'] is List) {
        setState(() {
          _vendors = (res['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
    }
  }

  // ─────────── Step 2: load orders for selected location ────────────────────
  Future<void> _fetchOrders() async {
    if (_selectedLocation == null) return;
    setState(() => _isLoading = true);
    try {
      final orgSubId = _selectedLocation!['id']?.toString() ?? '';
      String pstatusPayload = '';
      String astatusPayload = '';

      if (_selectedStatus != null) {
        final String statusId = (_selectedStatus!['id'] ?? '').toString();
        final String statusType = (_selectedStatus!['type'] ?? 'pstatus').toString();
        if (statusId.isNotEmpty) {
          if (statusType == 'astatus') {
            astatusPayload = statusId;
          } else {
            pstatusPayload = statusId;
          }
        }
      }

      final String vendorParam    = _selectedVendor?['id']?.toString() ?? '';
      final String docnoParam     = _docNoController.text.trim();
      final String sdateParam     = _startDate != null ? _fmtDate(_startDate!) : '';
      final String edateParam     = _endDate   != null ? _fmtDate(_endDate!)   : '';
      final String productIdParam = _filterProductId;
      final String refDocnoParam  = _refDocnoController.text.trim();
      final String remarkParam    = _remarkController.text.trim();
      final String itemRemarkParam = _itemRemarkController.text.trim();

      final response = await _controller.getPurchaseOrders(
        orgSubId: orgSubId,
        pstatus: pstatusPayload,
        astatus: astatusPayload,
        vendor: vendorParam,
        docno:  docnoParam,
        sdate:  sdateParam,
        edate:  edateParam,
        productId: productIdParam,
        refDocno:  refDocnoParam,
        remark: remarkParam,
        itemRemark: itemRemarkParam,
        limit: _pageSize,
        skip: _skip,
      );

      if (response['success'] == true && response['data'] != null) {
        setState(() {
          final dataList = response['data'] as List? ?? [];
          _orders = dataList.map((e) => PurchaseOrder.fromJson(e)).toList();

          // Try the common shapes a backend might report a grand total under.
          final dynamic rawTotal = response['total'] ??
              response['len'] ??
              response['total_records'] ??
              response['totalRecords'] ??
              response['recordsTotal'] ??
              response['record_total'] ??
              response['count'];

          if (rawTotal != null) {
            _totalRecords = int.tryParse(rawTotal.toString()) ?? _orders.length;
          } else {
            // No total reported at all. Falling back to `_orders.length`
            // breaks "Next" the moment a page comes back full — e.g. 30
            // rows on a 30-row page makes totalPages == 1 forever, even
            // with more records behind it. Instead, assume another page
            // exists whenever this page is completely full, and only
            // settle on the real total once a short (or empty) page comes back.
            _totalRecords = _orders.length == _pageSize
                ? _skip + _orders.length + 1
                : _skip + _orders.length;
          }
        });
      } else {
        setState(() {
          _orders = [];
          _totalRecords = 0;
        });
      }
    } catch (e) {
      setState(() {
        _orders = [];
        _totalRecords = 0;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onLocationChanged(Map<String, dynamic>? loc) {
    setState(() {
      _selectedLocation = loc;
      _selectedStatus = null;
      _selectedVendor = null;
      _docNoController.clear();
      _filterProductId   = '';
      _filterProductName = '';
      _refDocnoController.clear();
      _remarkController.clear();
      _itemRemarkController.clear();
      _startDate = null;
      _endDate   = null;
      _currentPage = 1;
      _skip = 0;
      _orders = [];
      _totalRecords = 0;
    });
    _fetchOrders();
  }

  void _resetPagination() {
    _currentPage = 1;
    _skip = 0;
  }

  // ────────────────────────── Navigation ────────────────────────────────────
  void _openCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => POFormScreen(onSave: (newOrder) => _fetchOrders(), initialLocationId:    _selectedLocation?['id']?.toString(), initialLocationLabel: _selectedLocation?['name']?.toString()),
      ),
    );
  }

  Future<void> _openUpdate(PurchaseOrder order) async {
    if (order.id.isEmpty) {
      if (!mounted) return;
      CommonUtils.showSnackBar(
        'Cannot load full details: record ID missing.',
        'danger',
        context,
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => POFormScreen(order: order, onSave: (_) => _fetchOrders()),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _controller.getPurchaseOrderDetail(formId: order.id);
      if (!mounted) return;

      PurchaseOrder fullOrder = order;

      if (res['success'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final Map<String, dynamic> header = data['header'] is Map
            ? Map<String, dynamic>.from(data['header'] as Map)
            : data;

        List<dynamic> rawMixed = [];
        for (final key in ['item', 'items', 'detail', 'line_items']) {
          if (data[key] is List && (data[key] as List).isNotEmpty) {
            rawMixed = data[key] as List;
            break;
          }
        }
        if (rawMixed.isEmpty) {
          for (final key in ['item', 'items', 'detail', 'line_items']) {
            if (header[key] is List && (header[key] as List).isNotEmpty) {
              rawMixed = header[key] as List;
              break;
            }
          }
        }

        List<Map<String, dynamic>> rawItems = [];
        List<Map<String, dynamic>> rawTrx   = [];
        List<Map<String, dynamic>> rawApprovalLog = [];

        void classifyRow(String rowName, Map<String, dynamic> inner) {
          if (rowName == 'trx code' || inner.containsKey('TRX Code') || inner.containsKey('trx_code')) {
            rawTrx.add({
              'code':   inner['TRX Code']?.toString() ?? inner['trx_code']?.toString() ?? inner['code']?.toString() ?? '',
              'amount': inner['Amount']?.toString()   ?? inner['amount']?.toString()   ?? '0',
              'remark': inner['Remark']?.toString()   ?? inner['remark']?.toString()   ?? '',
            });
          } else if (rowName == 'approval log' || inner.containsKey('Action By') || inner.containsKey('action_by')) {
            rawApprovalLog.add({
              'action':    inner['Action']?.toString()      ?? inner['action']?.toString()      ?? '',
              'action_by': inner['Action By']?.toString()   ?? inner['action_by']?.toString()   ?? '',
              'remark':    inner['Remark']?.toString()      ?? inner['remark']?.toString()      ?? '',
              'action_dt': inner['Action Date']?.toString() ?? inner['action_dt']?.toString()   ?? '',
            });
          } else {
            rawItems.add(inner);
          }
        }

        for (final element in rawMixed) {
          if (element is! Map) continue;
          final Map<String, dynamic> el = Map<String, dynamic>.from(element);
          final String rowName = (el['name'] ?? '').toString().toLowerCase();
          final numericKeys = el.keys.where((k) => int.tryParse(k) != null).toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

          if (numericKeys.isEmpty) {
            classifyRow(rowName, el);
          } else {
            for (final k in numericKeys) {
              if (el[k] is! Map) continue;
              classifyRow(rowName, Map<String, dynamic>.from(el[k] as Map));
            }
          }
        }

        fullOrder = PurchaseOrder.fromJson({
          ...order.toJson(),
          ...header,
          'id':           order.id,
          'item':         rawItems,
          'items':        rawItems,
          'trx':          rawTrx,
          'trx_items':    rawTrx,
          'approval_log': rawApprovalLog,
        });
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => POFormScreen(order: fullOrder, onSave: (_) => _fetchOrders()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => POFormScreen(order: order, onSave: (_) => _fetchOrders()),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ────────────────────────── Build ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final totalPages = (_totalRecords / _pageSize).ceil().clamp(1, double.infinity).toInt();
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(context.str.purchaseOrder, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline, color: AppTheme.primary(context)),
            onPressed: _selectedLocation != null ? _openCreate : null,
          ),
          IconButton(
            icon: Icon(
              _isFilterOpen ? Icons.filter_alt_off : Icons.filter_alt,
              color: AppTheme.primary(context),
            ),
            onPressed: () => setState(() => _isFilterOpen = !_isFilterOpen),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildLocationBar(),
            if (_isFilterOpen) Expanded(child: SingleChildScrollView(child: _buildAdvancedFilterPanel())),
            if (!_isFilterOpen)
              Expanded(
                child: _isLoadingLocations
                    ? const Center(child: CircularProgressIndicator())
                    : _selectedLocation == null
                    ? _buildSelectLocationPrompt()
                    : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _orders.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                  onRefresh: _fetchOrders,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) =>
                        _buildPOCard(_orders[index]),
                  ),
                ),
              ),
            if (_orders.isNotEmpty && !_isFilterOpen) _buildPaginationControls(totalPages),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Location bar ────────────────────────────────────
  Widget _buildLocationBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
      ),
      child: _isLoadingLocations
          ? const SizedBox(
        height: 36,
        child: Center(child: LinearProgressIndicator()),
      )
          : Row(
        children: [
          Icon(Icons.location_on_outlined, size: 18, color: AppTheme.primary(context)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Map<String, dynamic>>(
                value: _selectedLocation,
                isExpanded: true,
                isDense: true,
                menuWidth: MediaQuery.of(context).size.width - 32,
                hint: Text(
                  context.str.select,
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
                ),
                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context)),
                items: _locations.map((loc) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: loc,
                    child: Text(
                      loc['name']?.toString() ?? loc['id']?.toString() ?? '—',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _onLocationChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectLocationPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_on_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            context.str.select,
            style: TextStyle(color: AppTheme.textSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(context.str.noRecordFound, style: TextStyle(color: AppTheme.textSecondary(context))),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(onPressed: _currentPage > 1 ? () {
            setState(() {
              _currentPage = 1;
              _skip = 0;
            });
            _fetchOrders();
          } : null,
            child: Text(context.str.first)
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () {
                  setState(() {
                    _currentPage--;
                    _skip = (_currentPage - 1) * _pageSize;
                  });
                  _fetchOrders();
                }
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                '${context.str.page} $_currentPage / $totalPages',
                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary(context)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages
                    ? () {
                  setState(() {
                    _currentPage++;
                    _skip = (_currentPage - 1) * _pageSize;
                  });
                  _fetchOrders();
                }
                    : null,
              ),
            ],
          ),
          ElevatedButton(onPressed: _currentPage < totalPages ? () {
            setState(() {
              _currentPage = totalPages;
              _skip = (totalPages - 1) * _pageSize;
            });
            _fetchOrders();
          } : null,
              child: Text(context.str.last)
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Filter panel ─────────────────────────────────────
  Widget _buildAdvancedFilterPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _poStatuses.map((status) {
              final isSelected = _selectedStatus?['id'] == status['id'];
              return ChoiceChip(
                label: Text(status['name']?.toString() ?? '', style: const TextStyle(fontSize: 14)),
                selected: isSelected,
                selectedColor: AppTheme.primary(context).withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: isSelected ? AppTheme.primary(context) : AppTheme.textPrimary(context),
                ),
                onSelected: (_) {
                  setState(() {
                    _selectedStatus = status;
                    _resetPagination();
                  });
                  _fetchOrders();
                },
              );
            }).toList(),
          ),
          const Divider(height: 24),
          DropdownButtonFormField<Map<String, dynamic>>(
            initialValue: _selectedVendor,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.str.vendor,
              labelStyle: TextStyle(fontSize: 17, color:AppTheme.textPrimary(context)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: [
              DropdownMenuItem(value: null, child: Text(context.str.all, style: const TextStyle(fontSize: 13))),
              ..._vendors.map((v) => DropdownMenuItem(
                value: v,
                child: Text(v['name']?.toString() ?? '', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
              )),
            ],
            onChanged: (v) {
              setState(() { _selectedVendor = v; _resetPagination(); });
              _fetchOrders();
            },
          ),
          const SizedBox(height: 12),
          _filterTextField('${context.str.documentNum} / ${context.str.refNo}', _docNoController),
          const SizedBox(height: 12),
          _buildProductFilterField(),
          const SizedBox(height: 12),
          _filterTextField('PR ${context.str.document}', _refDocnoController),
          const SizedBox(height: 12),
          _filterTextField(context.str.remark, _remarkController),
          const SizedBox(height: 12),
          _filterTextField(context.str.itemRemark, _itemRemarkController),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    side: BorderSide(color: AppTheme.border(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() { _startDate = picked; _resetPagination(); });
                      _fetchOrders();
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(
                    _startDate == null ? context.str.dateStart : _fmtDate(_startDate!),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('—', style: TextStyle(color: AppTheme.textPrimary(context))),
              ),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    side: BorderSide(color: AppTheme.border(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? _startDate ?? DateTime.now(),
                      firstDate: _startDate ?? DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() { _endDate = picked; _resetPagination(); });
                      _fetchOrders();
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: Text(
                    _endDate == null ? context.str.dateEnd : _fmtDate(_endDate!),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedVendor = null;
                    _docNoController.clear();
                    _filterProductId   = '';
                    _filterProductName = '';
                    _refDocnoController.clear();
                    _remarkController.clear();
                    _itemRemarkController.clear();
                    _startDate = null;
                    _endDate   = null;
                    _selectedStatus = null;
                    _resetPagination();
                  });
                  _fetchOrders();
                },
                child: Text(context.str.reset, style: TextStyle(color: AppTheme.danger(context))),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isFilterOpen = false;
                    _resetPagination();
                  });
                  _fetchOrders();
                },
                child: Text(context.str.applyFilter),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────── Cards ────────────────────────────────────
  Widget _buildPOCard(PurchaseOrder order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openUpdate(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.docNo,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary(context),
                        fontSize: 17),
                  ),
                  _buildStatusBadge(order.status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.business, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.vendorName.isNotEmpty ? order.vendorName : order.vendor,
                      style: TextStyle(
                          fontSize: 15,
                          color: AppTheme.textPrimary(context),
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(_fmtDate(order.poDate), style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.tag_outlined, size: 17, color: AppTheme.textSecondary(context)),
                  const SizedBox(width: 6),
                  Text('${context.str.refNo}: ',
                    style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context))),
                  Expanded(
                      child: Text(
                        order.refNo.isNotEmpty ? order.refNo : '-',
                        style: TextStyle(fontSize: 15, color: AppTheme.textPrimary(context)),
                        overflow: TextOverflow.ellipsis,
                      )
                  )
                ]
              ),
              if (order.remark.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.comment_outlined, size: 15, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.remark,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppTheme.textPrimary(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.statusBgColor(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.statusColor(status)),
      ),
    );
  }

  // ──────────────────────── Product filter picker ──────────────────────────
  /// Tappable field that shows the selected product name (or a placeholder)
  /// and opens the product search bottom sheet on tap.
  Widget _buildProductFilterField() {
    final bool hasSelection = _filterProductName.isNotEmpty;
    return GestureDetector(
      onTap: _showProductSearchSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          border: Border.all(
            color: hasSelection ? AppTheme.primary(context) : AppTheme.border(context),
            width: hasSelection ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasSelection ? _filterProductName : context.str.product,
                style: TextStyle(
                  fontSize: 14,
                  color: hasSelection
                      ? AppTheme.textPrimary(context)
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasSelection)
              GestureDetector(
                onTap: () => setState(() {
                  _filterProductId   = '';
                  _filterProductName = '';
                  _resetPagination();
                }),
                child: Icon(Icons.close, size: 16, color: AppTheme.textPrimary(context)),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom sheet with a live-search field and a scrollable product list,
  Future<void> _showProductSearchSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => setModal(() => searchQuery = val.trim()),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: searchQuery.isEmpty
                            ? Center(
                          child: Text(
                            context.str.typeToSearchProducts,
                            style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 16),
                          ),
                        )
                            : FutureBuilder<Map<String, dynamic>>(
                          future: _controller.searchProducts(searchText: searchQuery),
                          builder: (ctx3, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final res  = snapshot.data;
                            final list = (res?['data'] as List? ?? []);
                            if (list.isEmpty) {
                              return Center(
                                child: Text(
                                  context.str.noProductsFound,
                                  style: TextStyle(color: AppTheme.textSecondary(context), fontSize: 16),
                                ),
                              );
                            }
                            return ListView.separated(
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx4, i) {
                                final prod = list[i] as Map<String, dynamic>;
                                final name = prod['name']?.toString() ??
                                    prod['product_name']?.toString() ?? '';
                                final code = prod['sku']?.toString() ??
                                    prod['code']?.toString() ?? '';
                                return ListTile(
                                  dense: true,
                                  title: Text(name, style: const TextStyle(fontSize: 13)),
                                  subtitle: code.isNotEmpty
                                      ? Text(code, style: const TextStyle(fontSize: 11))
                                      : null,
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

    if (result == null || !mounted) return;

    setState(() {
      _filterProductId   = result['id']?.toString() ?? '';
      _filterProductName = result['name']?.toString() ??
          result['product_name']?.toString() ?? '';
      _resetPagination();
    });
  }

  Widget _filterTextField(String hint, TextEditingController controller) {
    return TextField(
      controller: controller,
      onSubmitted: (_) {
        setState(_resetPagination);
        _fetchOrders();
      },
      onChanged: (_) {
        setState(_resetPagination);
      },
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color:AppTheme.textPrimary(context)),
        isDense: true,
        contentPadding: const EdgeInsets.all(10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}