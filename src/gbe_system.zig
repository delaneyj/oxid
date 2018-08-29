const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const Gbe = @import("gbe.zig");

// `SessionType` param to these functions must have have a field called `gbe`
// which is of type `Gbe.Session(...)`

// TODO - implement a system that exposes an iterator instead of running
// everything internally

// TODO - write tests for this stuff

pub fn build(
  comptime SessionType: type,
  comptime SelfType: type,
  comptime think: fn(*SessionType, SelfType)bool,
) fn(*SessionType)void {
  assert(@typeId(SelfType) == builtin.TypeId.Struct);

  const Impl = struct{
    fn runOne(
      gs: *SessionType,
      self_id: Gbe.EntityId,
      comptime MainComponentType: type,
      main_component: *MainComponentType,
    ) bool {
      // fill in the fields of the `self` structure
      var self: SelfType = undefined;
      inline for (@typeInfo(SelfType).Struct.fields) |field| {
        // if the field is of type EntityId, fill it in....
        if (field.field_type == Gbe.EntityId) {
          @field(self, field.name) = self_id;
          continue;
        }
        // otherwise, it must be a pointer to a component, or an optional
        // pointer to a component
        comptime const ComponentType = unpackComponentType(field.field_type);
        comptime const is_optional = @typeId(field.field_type) == builtin.TypeId.Optional;
        @field(self, field.name) =
          if (ComponentType == MainComponentType)
            main_component
          else if (is_optional)
            gs.gbe.find(self_id, ComponentType)
          else
            gs.gbe.find(self_id, ComponentType) orelse return true;
      }
      // call the think function
      return think(gs, self);
    }

    fn runAll(
      gs: *SessionType,
      comptime MainComponentType: type,
    ) void {
      var it = gs.gbe.iter(MainComponentType); while (it.next()) |object| {
        if (!runOne(gs, object.entity_id, MainComponentType, &object.data)) {
          gs.gbe.markEntityForRemoval(object.entity_id);
        }
      }
    }

    fn run(gs: *SessionType) void {
      // only if all fields are optional will we consider optional fields when
      // determining the best component type
      var all_fields_optional = true;

      inline for (@typeInfo(SelfType).Struct.fields) |field, i| {
        if (field.field_type != Gbe.EntityId and
            @typeId(field.field_type) != builtin.TypeId.Optional) {
          all_fields_optional = false;
        }
      }

      // decide which component type to do the outermost iteration over.
      // choose the component type with the lowest amount of active entities.
      var best: usize = @maxValue(usize);
      var which: ?usize = null;

      // go through the fields in the SelfType struct (where each field is
      // either an EntityId or a pointer to a component)
      inline for (@typeInfo(SelfType).Struct.fields) |field, i| {
        if (field.field_type == Gbe.EntityId) {
          continue;
        }
        if (@typeId(field.field_type) == builtin.TypeId.Optional and
            !all_fields_optional) {
          continue;
        }
        comptime const field_type = unpackComponentType(field.field_type);
        if (@field(&gs.gbe.components, @typeName(field_type)).count < best) {
          best = @field(&gs.gbe.components, @typeName(field_type)).count;
          which = i;
        }
      }

      // run the iteration
      // note: i can't just look up `which_index` in Struct.fields because of a
      // compiler bug https://github.com/ziglang/zig/issues/1435
      if (which) |which_index| {
        inline for (@typeInfo(SelfType).Struct.fields) |field, i| {
          if (field.field_type == Gbe.EntityId) {
            continue;
          }
          if (@typeId(field.field_type) == builtin.TypeId.Optional and
              !all_fields_optional) {
            continue;
          }
          comptime const field_type = unpackComponentType(field.field_type);
          if (i == which_index) {
            runAll(gs, field_type);
            return;
          }
        }
        unreachable;
      } else {
        std.debug.panic("no matches");
      }
    }

    fn unpackComponentType(comptime field_type: type) type {
      comptime var ft = field_type;
      if (@typeId(ft) == builtin.TypeId.Optional) {
        ft = @typeInfo(ft).Optional.child;
      }
      if (@typeId(ft) != builtin.TypeId.Pointer) {
        @compileError("field must be a pointer");
        unreachable;
      }
      ft = @typeInfo(ft).Pointer.child;
      return ft;
    }
  };

  return Impl.run;
}
