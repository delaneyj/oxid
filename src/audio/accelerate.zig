const zang = @import("zang");

const Instrument = @import("wave_begin.zig").Instrument;

pub const AccelerateVoice = struct {
  pub const NumOutputs = 1;
  pub const NumTemps = 2;
  pub const Params = struct { playback_speed: f32 };

  pub const SoundDuration = 2.0;

  instrument: zang.Triggerable(Instrument),
  note_tracker: zang.Notes(Instrument.Params).NoteTracker,

  pub fn init() AccelerateVoice {
    const SongNote = zang.Notes(Instrument.Params).SongNote;
    const speed = 0.125;

    return AccelerateVoice {
      .instrument = zang.initTriggerable(Instrument.init()),
      .note_tracker = zang.Notes(Instrument.Params).NoteTracker.init([]SongNote {
        // same as wave_begin but with some notes chopped off
        SongNote { .params = Instrument.Params { .freq = 43.0, .note_on = true }, .t = 0.0 * speed },
        SongNote { .params = Instrument.Params { .freq = 36.0, .note_on = true }, .t = 1.0 * speed },
        SongNote { .params = Instrument.Params { .freq = 40.0, .note_on = true }, .t = 2.0 * speed },
        SongNote { .params = Instrument.Params { .freq = 45.0, .note_on = true }, .t = 3.0 * speed },
        SongNote { .params = Instrument.Params { .freq = 43.0, .note_on = true }, .t = 4.0 * speed },
        SongNote { .params = Instrument.Params { .freq = 35.0, .note_on = true }, .t = 5.0 * speed },
        SongNote { .params = Instrument.Params { .freq = 38.0, .note_on = true }, .t = 6.0 * speed },
        SongNote { .params = Instrument.Params { .freq = 38.0, .note_on = false }, .t = 7.0 * speed },
      }),
    };
  }

  pub fn reset(self: *AccelerateVoice) void {
    self.instrument.reset();
    self.note_tracker.reset();
  }

  pub fn paint(self: *AccelerateVoice, sample_rate: f32, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, params: Params) void {
    for (self.note_tracker.begin(sample_rate / params.playback_speed, outputs[0].len)) |*impulse| {
      impulse.note.params.freq *= params.playback_speed;
    }
    self.instrument.paintFromImpulses(sample_rate, outputs, temps, self.note_tracker.finish());
  }
};
