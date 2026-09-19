/** Short, locally synthesized mechanical effects. No downloads or audio autoplay. */
export class WorkbenchSound {
  private context?: AudioContext;
  private master?: GainNode;
  private noise?: AudioBuffer;
  muted = false;
  played = 0;
  lastEffect = '';

  unlock() {
    try {
      if (!this.context) {
        this.context = new AudioContext({ latencyHint: 'interactive' });
        this.master = this.context.createGain();
        this.master.gain.value = this.muted ? 0 : .45;
        this.master.connect(this.context.destination);
        this.noise = this.context.createBuffer(1, this.context.sampleRate, this.context.sampleRate);
        const data = this.noise.getChannelData(0);
        for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      }
      if (this.context.state === 'suspended') void this.context.resume().catch(() => {});
    } catch { /* Audio availability must never block interaction. */ }
  }

  setMuted(muted: boolean) {
    this.muted = muted;
    if (this.master && this.context) this.master.gain.setTargetAtTime(muted ? 0 : .45, this.context.currentTime, .015);
  }

  play(effect: 'open' | 'close' | 'pickup' | 'place' | 'unplug' | 'plug' | 'unscrew') {
    this.unlock();
    const ctx = this.context;
    if (!ctx || !this.master || !this.noise || this.muted) return;
    this.played++; this.lastEffect = effect;
    const start = ctx.currentTime + .006;
    const tone = (delay: number, frequency: number, duration: number, volume: number) => {
      const oscillator = ctx.createOscillator(), gain = ctx.createGain();
      oscillator.type = 'sine'; oscillator.frequency.setValueAtTime(frequency, start + delay);
      oscillator.frequency.exponentialRampToValueAtTime(frequency * .65, start + delay + duration);
      gain.gain.setValueAtTime(volume, start + delay);
      gain.gain.exponentialRampToValueAtTime(.0001, start + delay + duration);
      oscillator.connect(gain); gain.connect(this.master!);
      oscillator.start(start + delay); oscillator.stop(start + delay + duration);
      oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
    };
    const friction = (delay: number, duration: number, frequency: number, volume: number, attack = .003) => {
      const source = ctx.createBufferSource(), filter = ctx.createBiquadFilter(), gain = ctx.createGain();
      source.buffer = this.noise!;
      filter.type = 'bandpass'; filter.frequency.value = frequency; filter.Q.value = 1.4;
      gain.gain.setValueAtTime(.0001, start + delay);
      gain.gain.exponentialRampToValueAtTime(volume, start + delay + attack);
      gain.gain.exponentialRampToValueAtTime(.0001, start + delay + duration);
      source.connect(filter); filter.connect(gain); gain.connect(this.master!);
      source.start(start + delay); source.stop(start + delay + duration);
      source.onended = () => { source.disconnect(); filter.disconnect(); gain.disconnect(); };
    };
    if (effect === 'unscrew') {
      for (let i = 0; i < 5; i++) { friction(i * .11, .065, 1600, .18); tone(i * .11, 520, .04, .025); }
    } else if (effect === 'open') {
      // Latch releases immediately; quiet hinge friction follows the 550 ms lid motion.
      friction(0, .065, 2300, .6); tone(.009, 870, .10, .1);
      friction(.06, .40, 600, .16, .04); tone(.43, 160, .1, .09);
    } else if (effect === 'close') {
      friction(0, .36, 520, .12, .04);
      tone(.47, 125, .14, .26); friction(.47, .07, 1800, .5); tone(.51, 740, .06, .075);
    } else if (effect === 'unplug' || effect === 'plug') {
      friction(0, .1, 1200, .23); friction(.075, .035, 2800, .35);
      tone(.075, effect === 'plug' ? 760 : 1050, .045, .065);
    } else {
      friction(0, .08, 850, .15);
      tone(0, effect === 'place' ? 145 : 235, .09, .11);
    }
  }

  get state() { return this.context?.state ?? 'uninitialized'; }
  dispose() { if (this.context) void this.context.close(); }
}
