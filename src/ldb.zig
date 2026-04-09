const std = @import("std");
const assert = std.debug.assert;

const loggerdb = @import("loggerdb");

const DB_NAME = "test_db";
const TABLE_NAME = "test_table";

const LOGGERDB_OK = loggerdb.LOGGERDB_OK;

pub fn main() !void {
    std.debug.print("LOGGERDB_OK = {}\n", .{LOGGERDB_OK});

    std.debug.print("opening database\n", .{});
    var db: loggerdb.loggerdb = undefined;
    defer {
        std.debug.print("closing database\n", .{});
        assert(loggerdb.ldb_close(&db) == LOGGERDB_OK);
    }
    assert(loggerdb.ldb_open(DB_NAME, &db) == LOGGERDB_OK);

    std.debug.print("opening table\n", .{});
    var table: loggerdb.loggerdb_table = undefined;
    defer {
        std.debug.print("closing table\n", .{});
        assert(loggerdb.ldb_table_close(&table) == LOGGERDB_OK);
    }
    assert(loggerdb.ldb_table_open(&db, TABLE_NAME, &table) == LOGGERDB_OK);
    assert(loggerdb.ldb_table_valid(&table) == LOGGERDB_OK);
}
