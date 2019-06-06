const zang = @import("zang");

pub const Instrument = struct {
    pub const NumOutputs = 1;
    pub const NumTemps = 2;
    pub const Params = struct { sample_rate: f32, freq: f32, note_on: bool };
    pub const NoteParams = struct { freq: f32, note_on: bool };

    osc: zang.PulseOsc,
    env: zang.Envelope,

    pub fn init() Instrument {
        return Instrument {
            .osc = zang.PulseOsc.init(),
            .env = zang.Envelope.init(),
        };
    }

    pub fn paint(self: *Instrument, span: zang.Span, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, note_id_changed: bool, params: Params) void {
        zang.zero(span, temps[0]);
        self.osc.paint(span, [1][]f32{temps[0]}, [0][]f32{}, zang.PulseOsc.Params {
            .sample_rate = params.sample_rate,
            .freq = params.freq,
            .colour = 0.5,
        });
        zang.zero(span, temps[1]);
        self.env.paint(span, [1][]f32{temps[1]}, [0][]f32{}, note_id_changed, zang.Envelope.Params {
            .sample_rate = params.sample_rate,
            .attack_duration = 0.0,
            .decay_duration = 0.0,
            .sustain_volume = 1.0,
            .release_duration = 0.04,
            .note_on = params.note_on,
        });
        zang.multiplyWithScalar(span, temps[1], 0.25);
        zang.multiply(span, outputs[0], temps[0], temps[1]);
    }
};

pub const CoinVoice = struct {
    pub const NumOutputs = 1;
    pub const NumTemps = 2;
    pub const Params = struct {
        sample_rate: f32,
        freq_mul: f32,
    };
    pub const NoteParams = struct {
        freq_mul: f32,
    };

    pub const SoundDuration = 2.0;

    instrument: Instrument,
    trigger: zang.Trigger(Instrument.NoteParams),
    note_tracker: zang.Notes(Instrument.NoteParams).NoteTracker,

    pub fn init() CoinVoice {
        const SongNote = zang.Notes(Instrument.NoteParams).SongNote;

        return CoinVoice {
            .instrument = Instrument.init(),
            .trigger = zang.Trigger(Instrument.NoteParams).init(),
            .note_tracker = zang.Notes(Instrument.NoteParams).NoteTracker.init([]SongNote {
                SongNote { .params = Instrument.NoteParams { .freq = 750.0, .note_on = true }, .t = 0.0 },
                SongNote { .params = Instrument.NoteParams { .freq = 1000.0, .note_on = true }, .t = 0.045 },
                SongNote { .params = Instrument.NoteParams { .freq = 1000.0, .note_on = false }, .t = 0.090 },
            }),
        };
    }

    pub fn paint(self: *CoinVoice, span: zang.Span, outputs: [NumOutputs][]f32, temps: [NumTemps][]f32, note_id_changed: bool, params: Params) void {
        if (note_id_changed) {
            self.trigger.reset();
            self.note_tracker.reset();
        }

        var ctr = self.trigger.counter(span, self.note_tracker.consume(params.sample_rate, span.end - span.start));
        while (self.trigger.next(&ctr)) |result| {
            self.instrument.paint(result.span, outputs, temps, note_id_changed or result.note_id_changed, Instrument.Params {
                .sample_rate = params.sample_rate,
                .freq = result.params.freq * params.freq_mul,
                .note_on = result.params.note_on,
            });
        }
    }
};
