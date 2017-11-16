***日志记录
    INCLUDE zpp_mes_reservation_order_log.

*******接口调用
    DATA: ls_header TYPE zppt001.
    DATA: lt_item TYPE STANDARD TABLE OF zppt002.
    DATA: ls_item TYPE zppt002.
    DATA: lv_rspos TYPE i.

    MOVE-CORRESPONDING input-mt_mes_reservation_order-is_header TO ls_header.
    ls_header-plannedtime = input-mt_mes_reservation_order-is_header-planned_time.
    lv_rspos = 0.
    LOOP AT input-mt_mes_reservation_order-it_item INTO DATA(ls_mes_item).
      lv_rspos = lv_rspos + 1.
      CLEAR: ls_item.
      MOVE-CORRESPONDING ls_mes_item TO ls_item.
      ls_item-transfernum = input-mt_mes_reservation_order-is_header-transfernum.
      ls_item-rspos = lv_rspos.
      APPEND ls_item TO lt_item.
    ENDLOOP.


    DATA: lv_mytype TYPE bapi_mtype.
    DATA: lv_message TYPE bapi_mtype.
    CALL FUNCTION 'ZFM_PP_CREATE_RESERVEORDER'
      EXPORTING
        is_header  = ls_header
      IMPORTING
        ev_type    = lv_mytype
        ev_message = lv_message
      TABLES
        it_item    = lt_item.

**返回处理结果
    CALL FUNCTION 'ZFM_PP_COMMON_ACK_ITF'
      EXPORTING
        iv_guid    = lv_guid
        iv_type    = lv_mytype
        iv_message = lv_message
        iv_date    = sy-datum
        iv_time    = sy-uzeit.
		
		
INCLUDE zpp_mes_reservation_order_log.
*&---------------------------------------------------------------------*
*& 包含               ZPP_MES_RESERVATION_ORDER_LOG
***ZII_SI_MES_RESERVATION_ORDER~SI_MES_RESERVATION_ORDER  传入参数日志
*&---------------------------------------------------------------------*

******* 记录日志
    DATA: lv_guid TYPE sysuuid_c32.
    DATA: ls_log_header TYPE zppt004.
    DATA: ls_log_item TYPE zppt005.
    DATA: lt_log_item TYPE STANDARD TABLE OF zppt005.
    DATA: lv_process_type TYPE zprocess_type VALUE 'ZFM_PP_CREATE_RESERVEORDER'.

    lv_guid = input-mt_mes_reservation_order-is_msg_head-guid.

*****log抬头
    CLEAR: ls_log_header.
    ls_log_header-guid = lv_guid.
    ls_log_header-process_type = lv_process_type.
    ls_log_header-orderkey = input-mt_mes_reservation_order-is_header-transfernum.
    ls_log_header-direction = 'RECEIVER'.
    ls_log_header-username = sy-uname.
    ls_log_header-log_date = sy-datum.
    ls_log_header-log_time = sy-uzeit.

******log具体传输的数据
    DATA: lt_components TYPE abap_component_tab.
    DATA: ls_components LIKE LINE OF lt_components.
    DATA: structtype  TYPE REF TO cl_abap_structdescr.
    FIELD-SYMBOLS <fs_value> TYPE any .

*** IS_HEADER
    CLEAR: lt_components, structtype.
    structtype ?= cl_abap_typedescr=>describe_by_name( 'ZDT_MES_RESERVATION_ORDER_IS_H' ).     "1
    CALL METHOD structtype->get_components
      RECEIVING
        p_result = lt_components.
*    LOOP AT input-mt_mes_reservation_order-is_header INTO DATA(is_header).  "2
*    DATA: is_header TYPE zdt_mes_reservation_order_is_h.
*    MOVE-CORRESPONDING input-mt_mes_reservation_order-is_header TO is_header.
    LOOP AT lt_components INTO ls_components.
      CLEAR: ls_log_item.
      IF ls_components-name = 'CONTROLLER'.
        CONTINUE.
      ENDIF.
      ls_log_item-guid = lv_guid.
      ls_log_item-process_type = lv_process_type.
      ls_log_item-tabname = 'IS_HEADER'.  "3
      ls_log_item-tabkey = input-mt_mes_reservation_order-is_header-transfernum. "4

      ls_log_item-fname = ls_components-name.
      UNASSIGN: <fs_value>.
      ASSIGN COMPONENT ls_components-name OF STRUCTURE input-mt_mes_reservation_order-is_header TO <fs_value>. "5
      ls_log_item-value = <fs_value>.
      IF ls_log_item-value IS NOT INITIAL.
        APPEND ls_log_item TO lt_log_item.
      ENDIF.
    ENDLOOP.
*    ENDLOOP.

***IT_ITEM
    CLEAR: lt_components, structtype.
    structtype ?= cl_abap_typedescr=>describe_by_name( 'ZDT_MES_RESERVATION_ORDER_IT_I' ).     "1
    CALL METHOD structtype->get_components
      RECEIVING
        p_result = lt_components.
    LOOP AT input-mt_mes_reservation_order-it_item INTO DATA(is_item).  "2
      LOOP AT lt_components INTO ls_components.
        CLEAR: ls_log_item.
        IF ls_components-name = 'CONTROLLER'.
          CONTINUE.
        ENDIF.
        ls_log_item-guid = lv_guid.
        ls_log_item-process_type = lv_process_type.
        ls_log_item-tabname = 'IT_ITEM'.  "3
        ls_log_item-tabkey = input-mt_mes_reservation_order-is_header-transfernum && sy-tabix. "4

        ls_log_item-fname = ls_components-name.
        UNASSIGN: <fs_value>.
        ASSIGN COMPONENT ls_components-name OF STRUCTURE is_item TO <fs_value>. "5
        ls_log_item-value = <fs_value>.
        IF ls_log_item-value IS NOT INITIAL.
          APPEND ls_log_item TO lt_log_item.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    IF lt_log_item IS NOT INITIAL OR ls_log_header IS NOT INITIAL.
      CALL FUNCTION 'ZFM_PP_CREATE_LOG'
        EXPORTING
          is_header = ls_log_header
        TABLES
          it_item   = lt_log_item.
    ENDIF.
