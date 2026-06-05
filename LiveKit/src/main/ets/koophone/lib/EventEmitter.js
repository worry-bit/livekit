export default class EventEmitter {
    constructor() {
        this._listeners = {};
    }

    addListener(evt, listener) {
        if (!this._listeners[evt]) {
            this._listeners[evt] = [];
        }
        this._listeners[evt].push(listener);
    }

    removeListener(evt, listener) {
        const listeners = this._listeners[evt];
        if (!listeners) {
            return;
        }
        this._listeners[evt] = listeners.filter((item) => item !== listener);
    }

    removeAllListeners() {
        this._listeners = {};
    }

    emit(evt, ...args) {
        const listeners = this._listeners[evt] || [];
        listeners.forEach((listener) => listener(...args));
    }
}
