// Web Bluetooth for the Training Brain iPhone app. Safari (and so this app's web
// view) has no navigator.bluetooth; this provides the part of it the web app uses
// (requestDevice, gatt.connect, getPrimaryService, getCharacteristic,
// startNotifications, readValue, writeValue[WithoutResponse], and the
// characteristicvaluechanged / gattserverdisconnected events) and hands each call
// to the native side (BLEBridge.swift), which talks to CoreBluetooth.
(function () {
  if (navigator.bluetooth) return;
  const post = m => window.webkit.messageHandlers.tbble.postMessage(m);
  let seq = 0;
  const pending = {}, devices = {}, chars = {};
  const call = (op, args) => new Promise((res, rej) => {
    const id = ++seq;
    pending[id] = { res, rej };
    post({ id, op, args: args || {} });
  });
  // Web Bluetooth names for standard services/characteristics → full UUIDs.
  const ALIAS = {
    heart_rate: '180d', heart_rate_measurement: '2a37', battery_service: '180f', battery_level: '2a19',
    cycling_power: '1818', cycling_power_measurement: '2a63', cycling_speed_and_cadence: '1816',
    csc_measurement: '2a5b', fitness_machine: '1826', indoor_bike_data: '2ad2', device_information: '180a',
  };
  const uuid = u => {
    if (typeof u === 'number') u = u.toString(16).padStart(4, '0');
    u = String(u).toLowerCase();
    if (ALIAS[u]) u = ALIAS[u];
    if (/^[0-9a-f]{4}$/.test(u)) u = '0000' + u;
    if (/^[0-9a-f]{8}$/.test(u)) u += '-0000-1000-8000-00805f9b34fb';
    return u;
  };
  const toView = b64 => {
    const s = atob(b64 || ''), a = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
    return new DataView(a.buffer);
  };
  const toB64 = d => {
    const a = d instanceof ArrayBuffer ? new Uint8Array(d) : new Uint8Array(d.buffer, d.byteOffset || 0, d.byteLength);
    let s = '';
    for (let i = 0; i < a.length; i++) s += String.fromCharCode(a[i]);
    return btoa(s);
  };
  class Target {
    constructor() { this._l = {}; }
    addEventListener(t, f) { (this._l[t] = this._l[t] || []).push(f); }
    removeEventListener(t, f) { this._l[t] = (this._l[t] || []).filter(x => x !== f); }
    _fire(t) {
      const e = { type: t, target: this, currentTarget: this };
      for (const f of (this._l[t] || []).slice()) { try { f.call(this, e); } catch (x) { console.error(x); } }
      if (typeof this['on' + t] === 'function') { try { this['on' + t](e); } catch (x) { console.error(x); } }
    }
  }
  class Characteristic extends Target {
    constructor(service, id, u) { super(); this.service = service; this._id = id; this.uuid = u; this.value = null; }
    async startNotifications() { await call('notify', { c: this._id, on: true }); return this; }
    async stopNotifications() { await call('notify', { c: this._id, on: false }); return this; }
    async readValue() { this.value = toView(await call('read', { c: this._id })); return this.value; }
    writeValue(d) { return call('write', { c: this._id, b: toB64(d), resp: true }); }
    writeValueWithResponse(d) { return this.writeValue(d); }
    writeValueWithoutResponse(d) { return call('write', { c: this._id, b: toB64(d), resp: false }); }
  }
  class Service {
    constructor(device, id, u) { this.device = device; this._id = id; this.uuid = u; this.isPrimary = true; }
    async getCharacteristic(u) {
      u = uuid(u);
      const r = await call('char', { s: this._id, u });
      const c = new Characteristic(this, r.id, u);
      chars[r.id] = c; // the latest object for a characteristic gets its events
      return c;
    }
  }
  class Server {
    constructor(device) { this.device = device; this.connected = false; }
    async connect() { await call('connect', { d: this.device.id }); this.connected = true; return this; }
    disconnect() { this.connected = false; call('disconnect', { d: this.device.id }).catch(() => {}); }
    async getPrimaryService(u) {
      u = uuid(u);
      const r = await call('service', { d: this.device.id, u });
      return new Service(this.device, r.id, u);
    }
  }
  class Device extends Target {
    constructor(id, name) { super(); this.id = id; this.name = name; this.gatt = new Server(this); }
  }
  // Called by the native side.
  window.__tbBle = {
    done(id, ok, v) {
      const p = pending[id];
      if (!p) return;
      delete pending[id];
      if (ok) p.res(v);
      else {
        const e = new Error(String(v));
        e.name = /cancel/i.test(String(v)) ? 'NotFoundError' : 'NetworkError';
        p.rej(e);
      }
    },
    value(cid, b64) { const c = chars[cid]; if (c) { c.value = toView(b64); c._fire('characteristicvaluechanged'); } },
    dropped(did) { const d = devices[did]; if (d) { d.gatt.connected = false; d._fire('gattserverdisconnected'); } },
  };
  Object.defineProperty(navigator, 'bluetooth', {
    configurable: true,
    value: {
      _tbNative: true,
      getAvailability: async () => true,
      async requestDevice(o) {
        o = o || {};
        const filters = (o.filters || []).map(f => ({
          services: (f.services || []).map(uuid), name: f.name || null, namePrefix: f.namePrefix || null,
        }));
        const r = await call('request', { filters, all: !!o.acceptAllDevices });
        const d = devices[r.id] || new Device(r.id, r.name);
        devices[r.id] = d;
        return d;
      },
    },
  });
})();
