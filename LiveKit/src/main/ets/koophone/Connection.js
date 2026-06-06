import * as Constants from './Constants';
import SocketIO from 'socket.io-client';
import * as ErrCode from './ErrCode';
import log from './util/ConsoleLog';

const MESSAGE_TIMEOUT = 15000;
const START_TIMEOUT = 5000;

export const SignalState = {
    NEW: "new",
    CONNECTING: "connecting",
    CONNECTED: "connected",
    DISCONNECTED: "disconnected",
    AUTHORIZED: "authorized",
    CONNECT_TIMEOUT: "connect_timeout",
    CLOSED: "closed"
};

export const AuthCode = {
    SUCCESS: 0,
    INVALID_TOKEN: -1,
    TOKEN_EXPIRED: -2
};

export default class Connection {

    constructor(tag) {
        this._tag = tag;
        this._serverUrl = null;
        this._opts = null;
        this._state = SignalState.NEW;
        this._onMessage = null;
        this._onStateChange = null;
        this._onStart = null;
        this._onProviderUpdate = null;
        this._socket = null;
        this._startTimer = null;
        this._times = -1;
        this._isStartReply = false;
        this._messageTimer = null;
        this._connectCount = 0;
        this._authCode = AuthCode.INVALID_TOKEN;
    }

    get onMessage() {
        return this._onMessage;
    }

    set onMessage(fun) {
        this._onMessage = fun;
    }

    get onStateChange() {
        return this._onStateChange;
    }

    set onStateChange(fun) {
        this._onStateChange = fun;
    }

    get onStart() {
        return this._onStart;
    }

    set onStart(fun) {
        this._onStart = fun;
    }

    get onProviderUpdate() {
        return this._onProviderUpdate;
    }

    set onProviderUpdate(fun) {
        this._onProviderUpdate = fun;
    }

    destroy() {
        this._onMessage = null;
        this._onStateChange = null;
        this._onStart = null;
        this._releaseSocket();
        this._connectCount = 0;
        delete this._serverUrl;
        delete this._opts;
        delete this._authCode;
        this._state = SignalState.NEW;
    }

    open(rtcServer, opts) {
        if (this._socket !== null) {
            log.debug(this._tag, "The connection already opened.");
            return;
        }
        this._stateChange(SignalState.CONNECTING);
        this._serverUrl = rtcServer;
        this._opts = opts;
        this._opts.transports = ['websocket'];
        this._opts.reconnection = false;
        this._opts.forceNew = true;
        this._opts.timeout = 3000;
        this._opts.autoConnect = false;
        this._createSocket();
    }

    emitSignal(signal, payload) {
        if (this._socket && this._socket.connected && this._state === SignalState.AUTHORIZED) {
            this._socket.emit(signal, payload);
        } else {
            log.warn(this._tag, "Cause connection isn't authorized, send signal failed!")
        }
    }

    start(payload) {
        this._times = payload.times;
        this._isStartReply = false;
        this._startStartTimer();
        let thiz = this;
        setTimeout(function () {
            thiz.emitSignal("start", payload);
        }, 0);
    }

    emitMessage(type, to, payload) {
        log.debug(this._tag, 'sending ' + type + ' to ' + to);
        if (this._socket && this._socket.connected && this._state === SignalState.AUTHORIZED) {
            this._socket.emit('message', {
                to: to,
                type: type,
                payload: payload
            });
        } else {
            log.warn(this._tag, "Cause connection isn't authorized, ignore to send event")
        }
    }

    emitMessageAsync(type, to, payload) {
        let thiz = this;
        setTimeout(function () {
            thiz.emitMessage(type, to, payload);
        }, 0);
    }

    emitData(type, to, data) {
        if (this._socket && this._socket.connected && this._state === SignalState.AUTHORIZED) {
            log.debug(this._tag, 'sending ' + type + ' to ' + to);
            if (type === "init") {
                this._startMessageTimer();
            }
            this._socket.emit('message', {
                to: to,
                type: type,
                data: data
            });
        } else {
            log.warn(this._tag, "connection is disconnected, ignore to send event(%s)!", type);
        }
    }

    emitDataAsync(type, to, data) {
        let thiz = this;
        setTimeout(function () {
            thiz.emitData(type, to, data);
        }, 0);
    }

    _createSocket() {
        if (!this._serverUrl || !this._opts) {
            log.warn(this._tag, "signaling url and opts can't be null!");
            return;
        }
        if (!!this._socket) {
            log.warn(this._tag, "signaling connection is exist, no need to create again");
            return;
        }
        log.debug(this._tag, "connecting signaling server(%s).", this._serverUrl);
        this._socket = SocketIO.connect(this._serverUrl, this._opts);
        this._connectCount++;
        this._addEvents();
        this._socket.open();
    }

    _releaseSocket() {
        if (this._socket !== null) {
            log.debug(this._tag, "release signaling connection.");
            this._removeEvents();
            this._socket.close();
            this._socket = null;
        }
    }

    _addEvents() {
        if (!!this._socket) {
            this._socket.on('message', this._onSocketMessage.bind(this));
            this._socket.on('connect', this._onSocketConnect.bind(this));
            this._socket.on('disconnect', this._onSocketDisconnect.bind(this));
            this._socket.on('connect_error', this._onSocketConnectTimeout.bind(this));
            this._socket.on('reconnect_failed', this._onSocketConnectTimeout.bind(this));
            this._socket.on("authorize", this._onSocketAuthorize.bind(this));
            this._socket.on("start", this._onSocketStart.bind(this));
            this._socket.on("close", this._onSocketClose.bind(this));
            this._socket.on("providerUpdate", this._onSocketProviderUpdate.bind(this));
        }
    }

    _removeEvents() {
        if (!!this._socket) {
            this._socket.off();
        }
    }

    _onSocketConnect() {
        log.info(this._tag, "[signaling connection] connected !!");
        this._connectCount = 0;
        this._stateChange(SignalState.CONNECTED, (!!this._socket && !!this._socket.id) ? this._socket.id : "null");
    }

    _onSocketDisconnect(reason) {
        log.info(this._tag, "[signaling connection] disconnected ! reason:" + reason);
        this._stopMessageTimer();
        this._stopStartTimer();
        if (this._state === SignalState.CONNECTING ||
            this._state === SignalState.CONNECTED ||
            this._state === SignalState.AUTHORIZED) {
            this._stateChange(SignalState.DISCONNECTED, {
                code: this._authCode
            });
        }
    }

    _onSocketConnectTimeout() {
        log.error(this._tag, "[signaling connection] connect timeout !!");
        this._stopMessageTimer();
        this._stopStartTimer();
        if (this._state === SignalState.CONNECTING) {
            if (this._connectCount > 2) {
                this._stateChange(SignalState.CONNECT_TIMEOUT, {
                    code: ErrCode.ERR_SIGNAL_CONNECT_TIMEOUT
                });
            } else {
                this._releaseSocket();
                let thiz = this;
                setTimeout(function () {
                    log.debug(thiz._tag, "start reconnect signaling server");
                    thiz._createSocket()
                }, 1000);
            }
        }
    }

    _onSocketAuthorize(auth) {
        log.info(this._tag, "[signaling connection] onAuthorize:{}", auth);
        this._authCode = auth.code;
        if (auth.authorized) {
            this._stateChange(SignalState.AUTHORIZED);
        } else {
            log.error(this._tag, "[signaling connection] unauthorized!");
            this._stateChange(SignalState.CLOSED, {
                code: ErrCode.ERR_TOKEN
            });
        }
    }

    _onSocketMessage(message) {
        let type = message.type,
            from = message.from;
        log.debug(this._tag, 'received ' + type + ' from ' + from);
        if (type === "offer") {
            this._stopMessageTimer();
        }
        if (this._onMessage !== null) {
            this._onMessage(message);
        }
    }

    _onSocketStart(param) {
        this._stopStartTimer();
        if (this._onStart !== null && !this._isStartReply) {
            this._onStart(param);
        }
        this._isStartReply = true;
    }

    _onSocketClose(param) {
        log.info(this._tag, "[signaling connection] closed !!");
        log.debug(this._tag, "close params: {}", param);
        let arr = (!!param && !!param.reason) ? param.reason.split(Constants.REASON_SEPARATOR) : [];
        let code = ((arr.length >= 1) && ErrCode.getCode(arr[0])) || ErrCode.ERR_SIGNAL_EXIT_ROOM;
        this._stateChange(SignalState.CLOSED, {
            code: code,
            extra: (arr.length >= 2) ? arr[1] : undefined
        });
    }

    _onSocketProviderUpdate(param) {
        if (this._onProviderUpdate !== null) {
            this._onProviderUpdate(param);
        }
    }

    _stateChange(state, evt) {
        this._state = state;
        if (this._onStateChange !== null) {
            this._onStateChange(this._state, evt);
        }
    }

    _onMessageTimeout() {
        log.warn(this._tag, "[signaling connection] command is no response!");
        this._stateChange(SignalState.CLOSED, {
            code: ErrCode.ERR_SIGNAL_MESSAGE_TIMEOUT
        });
    }

    _startMessageTimer() {
        this._stopMessageTimer();
        this._messageTimer = setTimeout(this._onMessageTimeout.bind(this), MESSAGE_TIMEOUT);
    }

    _stopMessageTimer() {
        if (!!this._messageTimer) {
            clearTimeout(this._messageTimer);
            this._messageTimer = null;
        }
    }

    _onStartTimeout() {
        this._onSocketStart({
            code: ErrCode.ERR_START_TIMEOUT,
            message: "start command timeout",
            times: this._times > 0 ? this._times - 1 : 0
        });
    }

    _startStartTimer() {
        this._stopStartTimer();
        this._startTimer = setTimeout(this._onStartTimeout.bind(this), START_TIMEOUT);
    }

    _stopStartTimer() {
        if (!!this._startTimer) {
            clearTimeout(this._startTimer);
            this._startTimer = null;
        }
    }
};