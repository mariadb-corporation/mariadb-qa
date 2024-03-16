require("oltp_common")

local con
xid_counter = 0

function init()
end

function thread_init(thread_id)
   local drv = sysbench.sql.driver()
   con = drv:connect()
   con:query("alter table mysql.gtid_slave_pos engine=innodb")
end

-------------------------------------------------------------------------------
-------------------------Common functions--------------------------------------
-------------------------------------------------------------------------------

-- Execute query query under xa
function xa_wrap(thread_id, query_func, ...)
   local xid = thread_id
   local success, ret
   xid_counter = xid_counter + 1
   local xid_str = string.format(" '%u','%u',1", xid, xid_counter)
   
   con:query("XA START" .. xid_str);
   success, ret = pcall(query_func, thread_id, ...)

   if not success then
     -- type(ret) is "table" only if --mysql-ignore-errors contains the error,
     -- that's why start sysbench with --mysql-ignore-errors=1213,1614,1205
     if type(ret) == "table" and
        ret.errcode == sysbench.error.RESTART_EVENT and
        -- deadlock or lock wait timeout or dup key error
        (ret.sql_errno == 1213 or ret.sql_errno == 1205 or ret.sql_errno == 1062)
     then
        local retx
        pcall(con.query, con, "XA END" .. xid_str)
        con:query("XA ROLLBACK" .. xid_str)
     end
     error(ret)
   end

   con:query("XA END" .. xid_str)
   con:query("XA PREPARE" .. xid_str)
   con:query("XA COMMIT" .. xid_str)

--   check_reconnect()
end

-- Mix XA with non-XA queries
function xa_mix(thread_id, xa_pct, non_xa_func, ...)
  local if_xa = sysbench.rand.uniform(0, 100)
  if if_xa < xa_pct then
    non_xa_func(thread_id, ...)
  else
    xa_wrap(thread_id, non_xa_func,  ...)
  end
end

-- Mix updates, inserts and deletes
function dml_mix(thread_id, upd_pct, ins_pct, del_pct, upd_func, ins_func, del_func)
  local cur_query = sysbench.rand.uniform(0, 100)
  if cur_query <= upd_pct then
    upd_func()
  elseif cur_query <= (upd_pct + ins_pct) then
    ins_func()
  else
    del_func()
  end
end


-------------------------------------------------------------------------------
---------------------------bankfrm.sessionmgmt---------------------------------
-------------------------------------------------------------------------------
function b_sessionmgmt_ins_vals(i)
  return string.format("('%040d', '%099d%099d', %d, '%020d', '%015d')", i, i, i, i, i, i)
end

function b_sessionmgmt_set_vals(i)
  return string.format("SESSION_ID='%040d', USER_ID='%099d%099d', TIMESTAMP=%d, CHANNEL_ID='%020d', SERVER_NAME='%015d'", i, i, i, i, i, i)
end

function b_sessionmgmt_where_vals(i)
--  local index_num = sysbench.rand.uniform(0, 4)
  local result
--  if index_num == 0 then
    result = string.format("SESSION_ID='%040d'", i)
--  elseif index_num == 1 then
--    result = string.format("SERVER_NAME='%015d' AND TIMESTAMP=%d", i, i)
--  elseif index_num == 2 then
--    result = string.format("USER_ID='%099d%099d'", i, i)
--  else
--    result = string.format("CHANNEL_ID='%020d' AND TIMESTAMP=%d", i, i)
--  end
  return result
end

function create_b_sessionmgmt(con, table_num)
  local query
  query = [[
     CREATE TABLE IF NOT EXISTS `b_sessionmgmt` (
       `SESSION_ID` varchar(40) NOT NULL,
       `USER_ID` varchar(200) NOT NULL,
       `TIMESTAMP` bigint(20) NOT NULL,
       `CHANNEL_ID` varchar(20) NOT NULL,
       `SERVER_NAME` varchar(15) DEFAULT NULL,
          PRIMARY KEY (`SESSION_ID`),
          KEY `DBS_IDX5` (`SERVER_NAME`,`TIMESTAMP`),
          KEY `DBS_SESSMGMT_IDX3` (`USER_ID`),
          KEY `DBS_IDX2` (`CHANNEL_ID`,`TIMESTAMP`)
      ) Engine=InnoDB; ]]

  con:query(query)

  query = "INSERT INTO `b_sessionmgmt` VALUES"

  con:bulk_insert_init(query)

  for i = 0, sysbench.opt.table_size do
    query = b_sessionmgmt_ins_vals(i)
    con:bulk_insert_next(query)
  end

  con:bulk_insert_done()
end

function b_sessionmgmt_update()
  local old_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local new_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local query =  "UPDATE b_sessionmgmt SET " .. b_sessionmgmt_set_vals(new_num) .. " WHERE " .. b_sessionmgmt_where_vals(old_num)
  con:query(query)
end

function b_sessionmgmt_insert()
  local new_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local query = "INSERT INTO `b_sessionmgmt` VALUES " .. b_sessionmgmt_ins_vals(new_num)
  con:query(query)
end

function b_sessionmgmt_delete()
  local old_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local query = "DELETE FROM `b_sessionmgmt` WHERE " .. b_sessionmgmt_where_vals(old_num)
  con:query(query)
end

-------------------------------------------------------------------------------
---------------------------`bankfrm`.`dbs_random_number_mgr`-------------------
-------------------------------------------------------------------------------
function b_dbs_random_number_mgr_ins_vals(i)
  return string.format("('%040d', '%040d', %015d, '%d')", i, i, i, i)
end

function b_dbs_random_number_mgr_set_vals(i)
  return string.format("RANDOM_NUMBER='%040d', APPLICATION_RANDOM_NUMBER='%040d', SERVER_NAME='%015d', TIME_STAMP=%d", i, i, i, i)
end

function b_dbs_random_number_mgr_where_vals(i)
--  local index_num = sysbench.rand.uniform(0, 2)
--  if index_num == 0 then
    result = string.format("APPLICATION_RANDOM_NUMBER='%040d'", i)
--  else
--    result = string.format("SERVER_NAME=%015d AND TIME_STAMP=%d", i, i)
--  end
  return result
end

function create_b_dbs_random_number_mgr(con, table_num)
  local query
  query = [[
    CREATE TABLE `b_dbs_random_number_mgr` (
      `RANDOM_NUMBER` varchar(40) NOT NULL,
      `APPLICATION_RANDOM_NUMBER` varchar(40) NOT NULL,
      `SERVER_NAME` varchar(15) NOT NULL,
      `TIME_STAMP` bigint(20) NOT NULL,
      PRIMARY KEY (`APPLICATION_RANDOM_NUMBER`),
      KEY `DBS_IDX8` (`SERVER_NAME`,`TIME_STAMP`)
    ) Engine=InnoDB;
  ]]

  con:query(query)

  query = "INSERT INTO `b_dbs_random_number_mgr` VALUES"

  con:bulk_insert_init(query)

  for i = 0, sysbench.opt.table_size do
    query = b_dbs_random_number_mgr_ins_vals(i)
    con:bulk_insert_next(query)
  end

  con:bulk_insert_done()
end

function b_dbs_random_number_mgr_update()
  local old_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local new_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local query =  "UPDATE b_dbs_random_number_mgr SET " .. b_dbs_random_number_mgr_set_vals(new_num) .. " WHERE " .. b_dbs_random_number_mgr_where_vals(old_num)
  con:query(query)
end

function b_dbs_random_number_mgr_insert(i)
  local new_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local query = "INSERT INTO `b_dbs_random_number_mgr` VALUES " .. b_dbs_random_number_mgr_ins_vals(new_num)
  con:query(query)
end

function b_dbs_random_number_mgr_delete(i)
  local old_num = sysbench.rand.uniform(0, sysbench.opt.table_size*2)
  local query = "DELETE FROM `b_dbs_random_number_mgr` WHERE " .. b_dbs_random_number_mgr_where_vals(old_num)
  con:query(query)
end

----------------------You can add more tables here ----------------------------

-------------------------------------------------------------------------------
----------------------Main loop------------------------------------------------
-------------------------------------------------------------------------------

function create_table(drv, con, table_num)
  create_b_sessionmgmt(con, table_num)
  create_b_dbs_random_number_mgr(con, table_num)
end

function event(thread_id)
  local b_sessionmgmt_pct = 98
  local b_dbs_random_number_mgr_pct = 2

  local table = sysbench.rand.uniform(0, 100)
  if table < b_sessionmgmt_pct
  then
    xa_mix(thread_id, 0, dml_mix, 80, 10, 10, b_sessionmgmt_update, b_sessionmgmt_insert, b_sessionmgmt_delete)
  else
    xa_mix(thread_id, 0, dml_mix, 10, 45, 45, b_dbs_random_number_mgr_update, b_dbs_random_number_mgr_insert, b_dbs_random_number_mgr_delete)
  end
end
