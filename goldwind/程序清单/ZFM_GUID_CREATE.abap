FUNCTION ZFM_GUID_CREATE.
*"----------------------------------------------------------------------
*"*"本地接口：
*"  EXPORTING
*"     REFERENCE(EV_GUID) TYPE  STRING
*"----------------------------------------------------------------------
  data:lv_guid type SYSUUID_C32.
  TRY.
    CALL METHOD cl_system_uuid=>if_system_uuid_static~create_uuid_c32
      RECEIVING
        uuid = lv_guid.
  CATCH cx_uuid_error .
     ENDTRY.
  ev_guid = lv_guid.                  "传GUID
  clear:lv_guid.
ENDFUNCTION.
