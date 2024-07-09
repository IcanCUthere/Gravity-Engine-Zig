const std = @import("std");
const mem = @import("memory.zig");

pub const Range = struct {
    index: usize,
    size: usize,
};

pub fn StableArray(comptime T: type) type {
    return struct {
        const Self = @This();
        const ItemContainer = std.ArrayList(T);
        const HoleContainer = std.ArrayList(Range);
        const DataId = usize;

        //elements will have the same index forever, until they are removed
        data: ItemContainer,

        //ordered after range.index
        holes: HoleContainer,

        pub fn init(allocator: std.mem.Allocator, itemCapacity: usize, holeCapacity: usize) !Self {
            return .{
                .data = try ItemContainer.initCapacity(allocator, itemCapacity),
                .holes = try HoleContainer.initCapacity(allocator, holeCapacity),
            };
        }

        pub fn add(self: *Self, newData: T) !DataId {
            //check if there is a hole we can fill
            if (self.holes.items.len > 0) {
                var range = self.holes.getLast();
                self.data.items[range.index] = newData;
                range.index += 1;
                range.size -= 1;

                if (range.size == 0) {
                    _ = self.holes.pop();
                } else {
                    self.holes.items[self.holes.items.len - 1] = range;
                }

                return range.index - 1;
            }
            //just add it
            else {
                const new = try self.data.addOne();
                new.* = newData;
                return self.data.items.len - 1;
            }
        }

        pub fn remove(self: *Self, id: DataId) !T {
            if (id == self.data.items.len - 1) {
                const removed = self.data.pop();

                //maybe there is a hole at the end, which just should not be part of the array
                if (self.holes.getLastOrNull()) |lasthole| {
                    if (lasthole.index + lasthole.size == self.data.items.len) {
                        _ = self.holes.pop();
                        try self.data.resize(lasthole.index);
                    }
                }

                return removed;
            } else {
                const removed = self.data.items[id];

                //we need to check if we can add it to a hole or create a new one
                const found = for (self.holes.items, 0..) |*range, i| {
                    //end of existing range
                    if (range.index + range.size == id) {
                        range.size += 1;

                        //stitch the this and the next hole together if they form a new range
                        if (self.holes.items.len > i + 1 and range.index + range.size == self.holes.items[i + 1].index) {
                            range.size += self.holes.items[i + 1].size;
                            _ = self.holes.orderedRemove(i + 1);
                        }

                        break true;
                    }
                    //start of existing range
                    else if (@subWithOverflow(range.index, 1).@"0" == id) {
                        range.index -= 1;
                        range.size += 1;
                        break true;
                    }

                    //because holes are ordered, we can be certain that we need a new hole, we couldnt add it to one
                    if (id < range.index) {
                        try self.holes.insert(i, Range{ .index = id, .size = 1 });
                        break true;
                    }
                } else false;

                if (!found) {
                    const new = try self.holes.addOne();
                    new.* = Range{ .index = id, .size = 1 };
                    return removed;
                }

                return removed;
            }
        }

        pub fn get(self: *Self, id: DataId) T {
            return self.data.items[id];
        }
    };
}
