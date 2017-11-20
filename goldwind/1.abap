  METHOD if_ex_mb_migo_badi~post_document.

******SAP&MES接口，SAP生产订单入库接口发送物料凭证信息到MES
data: lt_fm_row like stand table zpps006.

loop at it_mseg into data(ls_mseg)
call function ZFM_PP_PO_GR
tables
  it_row = lt_fm_row.

  ENDMETHOD.
