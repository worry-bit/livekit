# H5端 WebRTC 串流流程代码追踪

## 流程概述

```
1. H5端发起串流请求，与信令服务器建立socketio连接
2. 资管下发201消息到boxrtc，触发串流
3. boxrtc与信令服务器建立socketio连接
4. H5端发送init请求，boxrtc开始进行点对点连接的初始化
5. H5端接收到offer后记录remote sdp，发送answer
6. 两端发送candidate协商
7. 视频流通过WebRTC通道传输
```

---

## 1. H5端发起串流请求，与信令服务器建立socketio连接

### CloudPlayer.js

**`open()` 方法 (第137-146行)**
```javascript
open(params) {
    log.debug(this._tag, "======open player(%s)======", params.boxid);
    this._inBackground = false;
    if (this._state !== PlayerState.NEW && this._state !== PlayerState.CLOSED) {
        return undefined;
    }
    this._open(params);
}
```

**`_open()` 方法 (第642-662行)**
```javascript
_open(params) {
    if (!params.boxid || !params.uuid || (!params.token && !params.debugkey) || !params.signaling_url) {
        this._close(ErrCode.ERR_PARAM);
        return undefined;
    }
    this._session = {};
    Object.assign(this._session, params);
    this._createUserMedia();
    this._connect();  // 建立Socket.IO连接
}
```

**`_connect()` 方法 (第679-712行)**
```javascript
_connect() {
    this._authorized = false;
    this._connection = new Connection(this._tag);
    this._connection.onStateChange = this._onSignalConnectionStateChange.bind(this);
    this._connection.onMessage = this._onRemoteMessage.bind(this);
    this._connection.onStart = this._onStart.bind(this);
    this._connection.onProviderUpdate = this._onProviderUpdate.bind(this);

    let opts = {};
    if (!!this._session.authtype && this._session.authtype === "debug") {
        opts.query = "authtype=debug&boxid=" + this._session.boxid + "&debugkey=" + this._session.debugkey;
    } else {
        opts.query = "authtype=token&boxid=" + this._session.boxid + "&token=" + this._session.token;
    }
    this._connection.open(this._session.signaling_url, opts);
}
```

### Connection.js

**`open()` 方法 (第89-103行)**
```javascript
open(rtcServer, opts) {
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
```

**`_createSocket()` 方法 (第166-180行)**
```javascript
_createSocket() {
    log.debug(this._tag, "connecting signaling server(%s).", this._serverUrl);
    this._socket = SocketIO.connect(this._serverUrl, this._opts);  // 实际建立Socket.IO连接
    this._connectCount++;
    this._addEvents();
    this._socket.open();
}
```

---

## 2. H5端发送init请求

### CloudPlayer.js

**`_startStreaming()` 方法 (第911-919行)**
```javascript
_startStreaming(resetAspect) {
    this._createMediaElement();
    this._createInput();
    this._createPeer(resetAspect);
}
```

**`_createPeer()` 方法 (第1047-1122行)**
```javascript
_createPeer(resetAspect) {
    this._stateChange(PlayerState.PEER_CONNECTING, false, true);
    this._source = new RTCSource(this._tag, this._session.ice_servers, this._options.cameraCodecUseVP8);
    this._source.on("connectionstatechange", this._onConnectionStateChange.bind(this));
    this._source.on("track", this._onTrack.bind(this));
    this._source.on("icecandidate", this._onLocalIceCandidate.bind(this));
    this._source.on("description", this._onLocalDescription.bind(this));
    this._source.on("datachannel", this._onDataChannel.bind(this));
    this._source.on("error", this._onError.bind(this));
    this._source.on("statistics", this._onStatistics.bind(this));
    this._source.on("candidatepair", this._onCandidatePair.bind(this));

    this._source.open();  // 创建RTCPeerConnection

    let params = {
        "sole": this._options.sole,
        "mode": this._options.mode,
        "role": this._options.role,
        "profile_name": this._options.profileName || (this._options.primary ? "master" : "groupControl"),
        "network_type": Utils.getNetworkType(this._tag),
        "profile": this._profileLevel,
        "volume": this._session.muted ? 0 : 100,
        "vcodec": this._vcodec,
        // ...
    };

    let data = JSON.stringify(params);
    if (this._connection) {
        this._connection.emitDataAsync("init", this._remoteId, btoa(data));  // 发送init请求
    }
}
```

---

## 3. H5端接收到offer后发送answer

### CloudPlayer.js

**`_onRemoteMessage()` 方法 (第803-827行)**
```javascript
_onRemoteMessage(message) {
    let type = message.type;
    let payload = message.payload;
    if (!payload && !!message.data) {
        payload = JSON.parse(Base64.decode(message.data));
    }
    switch (type) {
        case "offer":
        case "answer":
            this._onRemoteDescription(payload);  // 处理offer
            break;
        case "candidate":
            this._onRemoteIceCandidate(payload);
            break;
    }
}
```

**`_onRemoteDescription()` 方法 (第2615-2618行)**
```javascript
_onRemoteDescription(payload) {
    if (this._source) {
        this._source.setRemoteDescription(payload);  // 设置remote SDP
    }
}
```

**`_onLocalDescription()` 方法 (第2690-2698行)**
```javascript
_onLocalDescription(sessionDescription) {
    if (sessionDescription && this._connection) {
        if (sessionDescription.type === "offer") {
            this._connection.emitMessageAsync("offer", this._remoteId, sessionDescription);
        } else {
            this._connection.emitMessageAsync("answer", this._remoteId, sessionDescription);  // 发送answer
        }
    }
}
```

### RTCSource.js

**`setRemoteDescription()` 方法 (第134-149行)**
```javascript
setRemoteDescription(params) {
    let thiz = this;
    let sessionDescription = new RTCSessionDescription(params);
    this._peerConn.setRemoteDescription(sessionDescription).then(function () {
        thiz._remoteParams = params;
        if ("offer" === params.type) {
            thiz.createAnswer();  // 收到offer时创建answer
        }
    }).catch(function (e) {
        log.error(thiz._tag, "Failure during setRemoteDescription: " + e.message);
    })
}
```

**`createAnswer()` 方法 (第151-166行)**
```javascript
createAnswer() {
    let thiz = this;
    this._peerConn.createAnswer().then(function (sessionDescription) {
        sessionDescription.sdp = SdpUtils.refineStereo(sessionDescription.sdp);
        return thiz._peerConn.setLocalDescription(sessionDescription);
    }).then(function () {
        if (thiz._emitter) {
            thiz._emitter.emit("description", thiz._peerConn.localDescription);  // 触发发送answer
        }
    }).catch(function (event) {
        log.error(thiz._tag, "Failure during createAnswer: " + event.message);
    })
}
```

---

## 4. Candidate协商

### 发送本地candidate

**RTCSource.js - `_onIceCandidate()` (第650-659行)**
```javascript
_onIceCandidate(event) {
    if (event.candidate) {
        if (event.candidate.sdpMid === "audio") {
            this._localCandidateMap[key] = event.candidate;
        }
        if (this._emitter) {
            this._emitter.emit("icecandidate", event);
        }
    }
}
```

**CloudPlayer.js - `_onLocalIceCandidate()` (第2678-2687行)**
```javascript
_onLocalIceCandidate(event) {
    if (event.candidate && this._connection) {
        let payload = {
            label: event.candidate.sdpMLineIndex,
            id: event.candidate.sdpMid,
            candidate: event.candidate.candidate
        };
        this._connection.emitMessageAsync("candidate", this._remoteId, payload);  // 发送candidate
    }
}
```

### 接收远端candidate

**CloudPlayer.js - `_onRemoteIceCandidate()` (第2621-2647行)**
```javascript
_onRemoteIceCandidate(payload) {
    if (this._source) {
        let iceCandidate = {
            sdpMLineIndex: payload.label,
            sdpMid: payload.id,
            candidate: payload.candidate
        };
        this._addRemoteIceCandidate(iceCandidate);  // 添加远端candidate
    }
}
```

**CloudPlayer.js - `_addRemoteIceCandidate()` (第2649-2660行)**
```javascript
_addRemoteIceCandidate(iceCandidate) {
    this._source.addRemoteIceCandidate(iceCandidate, 0);
    if (iceCandidate.sdpMid === "audio") {
        this._ipv6Candidate = SdpUtils.isIpv6(iceCandidate.candidate);
    }
}
```

**RTCSource.js - `addRemoteIceCandidate()` (第113-132行)**
```javascript
addRemoteIceCandidate(params, retry) {
    if (!this._peerConn.remoteDescription && retry < 20) {
        setTimeout(this.addRemoteIceCandidate.bind(this, params, retry + 1), 100);
    } else {
        let iceCandidate = new RTCIceCandidate(params);
        this._peerConn.addIceCandidate(iceCandidate).then(function () {
            log.debug(thiz._tag, "remote candidate message:{}", params);
        }).catch(function (e) {
            log.error(thiz._tag, "Failure during addIceCandidate: " + e.message);
        });
    }
}
```

---

## 5. 端侧接收视频流

**CloudPlayer.js - `_onTrack()` (第2662-2676行)**
```javascript
_onTrack(event) {
    log.debug(this._tag, "ontrack, track.kind = " + event.track.kind);
    if (!this._mediaElement) {
        return;
    }
    if (this._mediaElement.srcObject !== event.streams[0]) {
        this._mediaElement.srcObject = event.streams[0];  // 设置视频源
    }
}
```

**CloudPlayer.js - `_onPeerConnected()` (第1146-1175行)**
```javascript
_onPeerConnected() {
    if (this._state === PlayerState.PEER_CONNECTED || this._state === PlayerState.PLAYING) {
        return;
    }
    this._stateChange(PlayerState.PEER_CONNECTED);
    this._setupUIEvents();
    !!this._source && this._source.startStatistics();
    if (Utils.isiOS() && Utils.isWeixin()) {
        this._playVideoOnIOSWeixin();
    }
}
```

**CloudPlayer.js - `_playVideo()` (第1619-1654行)**
```javascript
_playVideo() {
    if (!this._mediaElement || !this._mediaElement.paused) {
        return;
    }
    let promise = !!this._mediaElement ? this._mediaElement.play() : undefined;
    if (promise !== undefined) {
        promise.then(function () {
            log.debug(thiz._tag, "Autoplay started!");
        }).catch(function () {
            // 处理自动播放失败
        });
    }
}
```

---

## 代码位置汇总表

| 步骤 | 功能 | 文件 | 方法 | 行号 |
|------|------|------|------|------|
| 1 | 发起串流 | CloudPlayer.js | `open()` | 137-146 |
| 1 | 参数校验 | CloudPlayer.js | `_open()` | 642-662 |
| 1 | 建立连接 | CloudPlayer.js | `_connect()` | 679-712 |
| 1 | Socket.IO | Connection.js | `_createSocket()` | 166-180 |
| 2 | 创建Peer | CloudPlayer.js | `_createPeer()` | 1047-1122 |
| 3 | 处理offer | CloudPlayer.js | `_onRemoteDescription()` | 2615-2618 |
| 3 | 创建answer | RTCSource.js | `createAnswer()` | 151-166 |
| 3 | 发送answer | CloudPlayer.js | `_onLocalDescription()` | 2690-2698 |
| 4 | 发送candidate | CloudPlayer.js | `_onLocalIceCandidate()` | 2678-2687 |
| 4 | 接收candidate | CloudPlayer.js | `_onRemoteIceCandidate()` | 2621-2647 |
| 4 | 添加candidate | RTCSource.js | `addRemoteIceCandidate()` | 113-132 |
| 5 | 连接完成 | CloudPlayer.js | `_onPeerConnected()` | 1146-1175 |
| 5 | 接收视频 | CloudPlayer.js | `_onTrack()` | 2662-2676 |
| 5 | 播放视频 | CloudPlayer.js | `_playVideo()` | 1619-1654 |

---

## 调用链路图

```
CloudPlayer.open()
    └── _open()
        └── _connect()
            └── Connection._createSocket()  ← Socket.IO连接建立

_onSignalConnectionStateChange(AUTHORIZED)
    └── _start()
        └── _onStart()
            └── _startStreaming()
                └── _createPeer()
                    ├── RTCSource.open()
                    └── emitDataAsync("init")  ← 发送init

收到offer → _onRemoteMessage("offer")
    └── _onRemoteDescription()
        └── RTCSource.setRemoteDescription()
            └── createAnswer()
                └── _onLocalDescription()
                    └── emitMessageAsync("answer")  ← 发送answer

candidate协商 → emitMessageAsync("candidate") / _onRemoteIceCandidate()
    └── RTCSource.addRemoteIceCandidate()

连接完成 → _onConnectionStateChange("connected")
    └── _onPeerConnected()
        └── _playVideo()  ← 播放视频
```

---

## 核心文件结构

```
src/
├── CloudPlayer.js     # 核心逻辑：状态机、信令收发、WebRTC流程控制
├── Connection.js      # Socket.IO连接管理
└── RTCSource.js       # RTCPeerConnection管理、SDP/Candidate处理
```