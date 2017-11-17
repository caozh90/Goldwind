*&---------------------------------------------------------------------*
*&      Form  FRM_PROCESS_CO11N
*&---------------------------------------------------------------------*
*       传输数据，进行完工入库和消耗物料确认
*----------------------------------------------------------------------*
*      -->P_LT_MSG  text
*      -->P_LS_IFDATAIN_ITEM  text
*      -->P_LS_IFDATAIN_HEAD  text
*      <--P_LV_EIND  text
*----------------------------------------------------------------------*
FORM frm_process_co11n  TABLES  tp_message STRUCTURE zifsret01
                                 tp_item STRUCTURE zrmxpps002
                        USING    up_head TYPE zrmxpps001
                        CHANGING cp_eind TYPE c
                                 cp_aufnr TYPE afko-aufnr
                                 cp_rueck TYPE afwi-rueck
                                 cp_rmzhl TYPE afwi-rmzhl.

 

  DATA:
        ls_item      TYPE zrmxpps002,
        ls_message   TYPE zifsret01.

  DATA: ls_afpo      TYPE ty_afpo,
        ls_afpo_find TYPE ty_afpo,
        lt_afpo      TYPE STANDARD TABLE OF ty_afpo,

        ls_status    TYPE ty_status,
        lt_status    TYPE STANDARD TABLE OF ty_status.


  DATA: lv_index TYPE i.
*--------------------------------------------------------------------*
*1 根据销售合同和行号，取得对应的生产订单号
  IF up_head-vtype = cns_vtype_1 OR   "对外销售-非来料加工类型合同
     up_head-vtype = cns_vtype_2.     "对外销售-来料加工类型合同
    "1,2为对外销售，需要根据销售订单号及行号读取对应的生产订单
    SELECT p~aufnr p~posnr
      INTO TABLE lt_afpo
      FROM afpo AS p
      WHERE p~kdauf = up_head-vbeln
        AND p~kdpos = up_head-posnr.
    IF sy-subrc NE 0.

      CLEAR ls_message.
      ls_message-class  = 'BUS'.
      ls_message-msgtyp = 'E'.
      ls_message-msgno  = '101'.
      ls_message-msgtxt = '根据销售合同和行号未找到相应的SAP生产订单号！'.
      APPEND ls_message TO tp_message.

      cp_eind = 'X'.
    ENDIF.

  ELSEIF up_head-vtype = cns_vtype_3. "站内自用
    "站内自用，需要根据生产出的物料的编码和工厂来找出合适的生产订单
    SELECT a~aufnr a~posnr
      INTO TABLE lt_afpo
      FROM afpo AS a INNER JOIN aufk AS b ON b~aufnr = a~aufnr
      WHERE a~matnr = up_head-matnr
        AND a~pwerk = up_head-werks  "计划工厂，todo 可能要用生产工厂
        AND b~auart = 'ZR02'.        "RMX自用生产订单
    IF sy-subrc NE 0.

      CLEAR ls_message.
      ls_message-class  = 'BUS'.
      ls_message-msgtyp = 'E'.
      ls_message-msgno  = '102'.
      ls_message-msgtxt = '根据物料号+工厂未找到相应的SAP生产订单号！'.
      APPEND ls_message TO tp_message.

      cp_eind = 'X'.
    ENDIF.
  ELSE.
    CLEAR ls_message.
    ls_message-class  = 'BUS'.
    ls_message-msgtyp = 'E'.
    ls_message-msgno  = '103'.
    ls_message-msgtxt = '销售合同类型定义错误！'.
    APPEND ls_message TO tp_message.

    cp_eind = 'X'.

  ENDIF.

  CHECK cp_eind NE 'X'.

  "合并对象号
  FIELD-SYMBOLS:<fs_afpo> LIKE ls_afpo.
  LOOP AT lt_afpo ASSIGNING <fs_afpo>.
    CONCATENATE 'OR' <fs_afpo>-aufnr INTO <fs_afpo>-objnr.
  ENDLOOP.


*--------------------------------------------------------------------*
*2 判断生产订单的状态，找到一个合适的生产订单
  SORT lt_afpo BY objnr.

  "读取状态
  SELECT objnr stat inact
    INTO TABLE lt_status
    FROM jest
    FOR ALL ENTRIES IN lt_afpo
    WHERE objnr EQ lt_afpo-objnr
      AND inact EQ space.

*  "删除未激活的状态
*  DELETE lt_status WHERE inact = 'X'.
  "删除不需要的状态
  DELETE lt_status WHERE "txt04 NE 'REL' AND  @v1.10
*                         txt04 NE 'CLSD' AND
*                         txt04 NE 'TECO'.
                          stat NE 'I0045' AND   "TECO
                          stat NE 'I0046' AND   "CLSD
                          stat NE 'E0001'.      "10

  SORT lt_status BY objnr stat.

*--------------------------------------------------------------------*
*3 生产订单的状态中必须包括TECO、不包括CLSD
  CLEAR ls_afpo_find.
  LOOP AT lt_afpo INTO ls_afpo.
    lv_index = sy-tabix.

    "系统状态必须包含TECO
    READ TABLE lt_status TRANSPORTING NO FIELDS
        WITH KEY objnr = ls_afpo-objnr
                 stat = 'I0045'
                 BINARY SEARCH.
    IF sy-subrc NE 0.
      DELETE lt_afpo INDEX lv_index.
      CONTINUE.
    ENDIF.

    "系统状态必须不包含CLSD
    READ TABLE lt_status TRANSPORTING NO FIELDS
        WITH KEY objnr = ls_afpo-objnr
                 stat = 'I0046'
                 BINARY SEARCH.
    IF sy-subrc EQ 0.
      DELETE lt_afpo INDEX lv_index.
      CONTINUE.
    ENDIF.

                                                            "用户状态必须为10
    READ TABLE lt_status TRANSPORTING NO FIELDS
        WITH KEY objnr = ls_afpo-objnr
                 stat = 'E0001'
                 BINARY SEARCH.
    IF sy-subrc NE 0.
      DELETE lt_afpo INDEX lv_index.
      CONTINUE.
    ENDIF.

    "找到生产订单，退出循环
    ls_afpo_find = ls_afpo.
    EXIT.

  ENDLOOP.

  IF ls_afpo_find IS INITIAL.
    CLEAR ls_message.
    ls_message-class  = 'BUS'.
    ls_message-msgtyp = 'E'.
    ls_message-msgno  = '104'.
    ls_message-msgtxt = '没有符合要求状态的生产订单！'.
    APPEND ls_message TO tp_message.

    cp_eind = 'X'.
  ENDIF.

  CHECK cp_eind NE 'X'.

  cp_aufnr = ls_afpo_find-aufnr.

*--------------------------------------------------------------------*
*4 Call BAPI
  DATA: ls_propose LIKE bapi_pp_conf_prop.

  DATA: lt_time  TYPE STANDARD TABLE OF bapi_pp_timeticket,
        ls_time  TYPE bapi_pp_timeticket,

        ls_goods TYPE bapi2017_gm_item_create,
        lt_goods TYPE STANDARD TABLE OF bapi2017_gm_item_create,

        ls_link  TYPE bapi_link_conf_goodsmov,
        lt_link  TYPE STANDARD TABLE OF bapi_link_conf_goodsmov,

        lt_return_detail TYPE STANDARD TABLE OF bapi_coru_return,
        ls_return_detail TYPE bapi_coru_return,
        ls_return        TYPE bapiret1.

*--------------------------------------------------------------------*
*4.1 需要更新的数据设置
  ls_propose-quantity      = 'X'.
  ls_propose-date_and_time = 'X'.
  ls_propose-goodsmovement = 'X'.

*--------------------------------------------------------------------*
*4.2 timeticket
  CLEAR ls_time.
  ls_time-orderid    = ls_afpo_find-aufnr.  "生产订单号
  ls_time-operation  = '0010'.                              "工序号：0010
  ls_time-postg_date = up_head-budat.       "记账日期
  ls_time-yield      = up_head-menge.       "生产数量
*ls_time-conf_quan_unit = 'PC'.
*ls_time-conf_quan_unit_iso = 'PC'.
  APPEND ls_time TO lt_time.

*--------------------------------------------------------------------*
*4.3 goodsmovements
* 第一次赋值，用于获取相关默认值
  CLEAR ls_goods.
  ls_goods-orderid    = ls_afpo_find-aufnr.  "生产订单号
  ls_goods-order_itno = '0010'.                             "工序号：0010
* VAL_TYPE 评估类型
  APPEND ls_goods TO lt_goods.

*4.4 调用BAPI，获取默认值
  CLEAR: ls_return.

  CALL FUNCTION 'BAPI_PRODORDCONF_GET_TT_PROP'
    EXPORTING
      propose            = ls_propose
    IMPORTING
      return             = ls_return
    TABLES
      timetickets        = lt_time
      goodsmovements     = lt_goods
      link_conf_goodsmov = lt_link
      detail_return      = lt_return_detail.

  IF ls_return-type = 'E' OR
     ls_return-type = 'A'.

    CLEAR ls_message.
    ls_message-class  = 'BUS'.
    ls_message-msgtyp = ls_return-type.
    ls_message-msgno  = ls_return-number.
    ls_message-msgtxt = ls_return-message.
    APPEND ls_message TO tp_message.

    cp_eind = 'X'.
  ENDIF.

  LOOP AT lt_return_detail INTO ls_return_detail
      WHERE type IS NOT INITIAL.

    CLEAR ls_message.
    ls_message-class  = 'BUS'.
    ls_message-msgtyp = ls_return_detail-type.
    ls_message-msgno  = ls_return_detail-number.
    ls_message-msgtxt = ls_return_detail-message.
    APPEND ls_message TO tp_message.

    IF ls_return_detail-type = 'E' OR
        ls_return_detail-type = 'A'.
      cp_eind = 'X'.
    ENDIF.
  ENDLOOP.

  CHECK cp_eind NE 'X'.

*4.5 若来自RMX系统的信息显示生产订单对应的销售合同为来料加工，
*    则需要由接口程序将默认带出的评估类型PRD改为OEM
  LOOP AT lt_goods INTO ls_goods.
    IF up_head-vtype = cns_vtype_2.
      ls_goods-val_type = 'OEM'.
    ELSE.
      ls_goods-val_type = 'PRD'.
    ENDIF.
    MODIFY lt_goods FROM ls_goods TRANSPORTING val_type.
  ENDLOOP.

*4.6 准备行项目数据
  "lt_goods中已经有生产订单对应的一条行记录，需要将传输的消耗物料信息
  "添加到内表中，进行确认，生成物料凭证
  CLEAR: ls_return, lt_return_detail.

  " 产量，lt_time 中默认是生产订单剩余未确认的产量
  LOOP AT lt_time INTO ls_time.
    ls_time-yield      = up_head-menge.  "产量
    ls_time-postg_date = up_head-budat.  "记账日起
    MODIFY lt_time FROM ls_time TRANSPORTING yield postg_date.
  ENDLOOP.

  "生产的物料，数量默认为未确认的全部数量
  LOOP AT lt_goods INTO ls_goods.
    ls_goods-entry_qnt = up_head-menge.  "产量
    MODIFY lt_goods FROM ls_goods TRANSPORTING entry_qnt.
  ENDLOOP.

  LOOP AT tp_item INTO ls_item.
    lv_index = sy-tabix.

    CLEAR ls_goods.
    ls_goods-material  = ls_item-matnr.
    ls_goods-move_type = '261'.
    ls_goods-plant     = ls_item-werks.
    ls_goods-stge_loc  = ls_item-lgort.                     "'0001'.
    ls_goods-entry_qnt = ls_item-menge.
    ls_goods-entry_uom = ls_item-meins.
*   ls_goods-entry_uom_iso = 'PCE'.
    APPEND ls_goods TO lt_goods.

    CLEAR ls_link.
    ls_link-index_confirm = 1.
    ls_link-index_goodsmov = lv_index + 1.
    APPEND ls_link TO lt_link.

  ENDLOOP.


  CALL FUNCTION 'BAPI_PRODORDCONF_CREATE_TT'
*   EXPORTING
*   POST_WRONG_ENTRIES       = '0'
*     testrun                  = ''
   IMPORTING
     return                   = ls_return
    TABLES
     timetickets              = lt_time
     goodsmovements           = lt_goods
     link_conf_goodsmov       = lt_link
     detail_return            = lt_return_detail
            .

  IF ls_return-type = 'E' OR
     ls_return-type = 'A'.

    CLEAR ls_message.
    ls_message-class  = 'BUS'.
    ls_message-msgtyp = ls_return-type.
    ls_message-msgno  = ls_return-number.
    ls_message-msgtxt = ls_return-message.
    APPEND ls_message TO tp_message.

    cp_eind = 'X'.

  ENDIF.

  LOOP AT lt_return_detail INTO ls_return_detail
      WHERE type IS NOT INITIAL.

    CLEAR ls_message.
    ls_message-class  = 'BUS'.
    ls_message-msgtyp = ls_return_detail-type.
    ls_message-msgno  = ls_return_detail-number.
    CONCATENATE ls_return_detail-message
                ';确认号:' ls_return_detail-conf_no
                ';计数器:' ls_return_detail-conf_cnt
           INTO ls_message-msgtxt .
    APPEND ls_message TO tp_message.

    IF ls_return_detail-type = 'E' OR
       ls_return_detail-type = 'A'.
      cp_eind = 'X'.
    ELSE.
      IF ls_return_detail-conf_no IS NOT INITIAL.
        cp_rueck = ls_return_detail-conf_no.  "确认号
        cp_rmzhl = ls_return_detail-conf_cnt. "计数器
      ENDIF.
    ENDIF.
  ENDLOOP.

  IF cp_eind NE 'X'.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = 'X'.
  ELSE.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
  ENDIF.

  CHECK  cp_eind NE 'X'.

  CLEAR afwi.
  DO 5 TIMES.

    SELECT SINGLE *
    FROM afwi
    WHERE rueck = cp_rueck
      AND rmzhl = cp_rmzhl.
*    IF sy-subrc EQ 0.
    IF afwi-mjahr IS NOT INITIAL.
      EXIT.
    ELSE.
      WAIT UP TO 1 SECONDS.
    ENDIF.

  ENDDO.

  IF afwi IS INITIAL.
    ls_message-class  = 'BUS'.
    ls_message-msgtyp = 'W'.
    ls_message-msgno  = '000'.
    ls_message-msgtxt = '生产完工入库物料凭证未生成成功，请人工处理！'.
    APPEND ls_message TO tp_message.
  ENDIF.

ENDFORM.                    " FRM_PROCESS_CO11N
