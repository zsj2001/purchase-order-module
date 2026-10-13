class PurchaseOrderApi {
  static const String listing   = '/public/api.php?go=module&mod=IVMS&page=mapi&act=get_all_purchase_order&styp=1';
  static const String submit = '/public/api.php?go=module&mod=IVMS&page=mapi&act=submit_purchase_order&styp=1';
  static const String locations = '/public/api.php?go=module&mod=IVMS&page=mapi&act=get_location_list&styp=1';
  static const String options   = '/public/api.php?go=module&mod=IVMS&page=mapi&act=purchase_order_requirement&styp=1';
  static const String products  = '/public/api.php?go=module&mod=IVMS&page=mapi&act=ajax_search_purchase_product_listing&styp=1';
  static const String productDetail = '/public/api.php?go=module&mod=IVMS&page=mapi&act=ajax_get_product_detail&styp=1';
  static const String detail = '/public/api.php?go=module&mod=IVMS&page=mapi&act=purchase_order_detail&styp=1';
  static const String poStatus = '/public/api.php?go=module&mod=IVMS&page=mapi&act=get_po_status';
  static const String vendorListing = '/public/api.php?go=module&mod=IVMS&page=mapi&act=get_all_vendor_list';
}