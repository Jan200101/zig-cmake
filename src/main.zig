const std = @import("std");
const assert = std.debug.assert;

const loggerdb = @import("loggerdb");

const DB_NAME = "test_db";
const TABLE_NAME = "test_table";

const LOGGERDB_OK = loggerdb.LOGGERDB_OK;

pub fn main() !void {
    std.debug.print("LOGGERDB_OK = {}\n", .{LOGGERDB_OK});

    var db: loggerdb.loggerdb = undefined;
    defer assert(loggerdb.ldb_close(&db) == LOGGERDB_OK);
    assert(loggerdb.ldb_open(DB_NAME, &db) == LOGGERDB_OK);

    var table: loggerdb.loggerdb_table = undefined;
    defer assert(loggerdb.ldb_table_close(&table) == LOGGERDB_OK);
    assert(loggerdb.ldb_table_open(&db, TABLE_NAME, &table) == LOGGERDB_OK);
    assert(loggerdb.ldb_table_valid(&table) == LOGGERDB_OK);
}
