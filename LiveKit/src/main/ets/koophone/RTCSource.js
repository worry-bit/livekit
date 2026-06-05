import './lib/WebRTCAdapter';
import EventEmitter from './lib/EventEmitter';
import SdpUtils from './util/SdpUtils';
import Utils from "./util/Utils";
import * as ErrCode from './ErrCode';
import {ICE_SERVERS} from './Constants';
import log from './util/ConsoleLog';
import {LOGLEVEL} from './Version';

export default class RTCSource {

    constructor(tag, iceServers, cameraCodecUseVP8) {
        this._tag = tag;
        this._emitter = new EventEmitter();
        this._peerConn = null;
        this._pcListeners = {};
        this._remoteParams = null;
        this._remoteCandidateMap = {};
        this._localCandidateMap = {};
        this._candidataTypes = ["relay", "prflx", "srflx", "host"];
        this._cameraOn = false;
        this._cameraCodecUseVP8 = cameraCodecUseVP8;
        let servers = undefined;
        if (!!iceServers && iceServers.length > 0) {
            servers = [];
            for (let i = 0; i < iceServers.length; i++) {
                servers.push({
                    urls: iceServers[i].uri,
                    username: iceServers[i].usr,
                    credential: iceServers[i].pwd
                })
            }
        }
        this._peerConnectionConfig = {
            iceServers: servers || ICE_SERVERS
        };
        this._peerConnectionConstraints = {
            optional: [
                {"DtlsSrtpKeyAgreement": true},
                {"googCpuOveruseDetection": false}
            ]
        };
        log.debug(this._tag, "RtcSource is created.");
    }

    destroy() {
        this.close();
        if (this._emitter) {
            this._emitter.removeAllListeners();
            this._emitter = null;
        }
        delete this._remoteParams;
        delete this._remoteCandidateMap;
        delete this._localCandidateMap;
        delete this._candidataTypes;
        delete this._peerConnectionConfig;
        delete this._peerConnectionConstraints;
        log.debug(this._tag, "RtcSource is destroyed.");
    }

    on(evt, listener) {
        if (this._emitter) {
            this._emitter.addListener(evt, listener);
        }
    }

    off(evt, listener) {
        if (this._emitter) {
            this._emitter.removeListener(evt, listener);
        }
    }

    open() {
        if (this._peerConn) {
            log.info(this._tag, "PeerConnection is already open.");
            return;
        }
        try {
            if (!Utils.supportRTCPeerConnection()) {
                if (this._emitter) {
                    this._emitter.emit("error", ErrCode.ERR_UNSUPPORT_BROWSER);
                }
                return;
            }
            log.trace(this._tag, "create RTCPeerConnection with config:%O", this._peerConnectionConfig);
            this._peerConn = new RTCPeerConnection(this._peerConnectionConfig, this._peerConnectionConstraints);
            this._addPCEventListeners();
            this.startStatistics();
            log.info(this._tag, "PeerConnection create success.");
        } catch (e) {
            log.error(this._tag, "RTCSource Failure create peerconnection: " + e.message);
            if (this._emitter) {
                this._emitter.emit("error", ErrCode.ERR_UNSUPPORT_BROWSER);
            }
        }
    }

    close() {
        if (!!this._peerConn) {
            log.debug(this._tag, "start to close peer connection.");
            this._removeLocalStream();
            this.stopStatistics();
            let thiz = this;
            let keys = Object.keys(this._pcListeners);
            keys.forEach(function (item) {
                thiz._removePCEventListener(item);
            });
            this._peerConn.close();
            delete this._peerConn;
        }
    }

    addRemoteIceCandidate(params, retry) {
        if (!this._peerConn.remoteDescription && retry < 20) {
            setTimeout(this.addRemoteIceCandidate.bind(this, params, retry + 1), 100);
        } else {
            let thiz = this;
            let iceCandidate = new RTCIceCandidate(params);
            if (iceCandidate.sdpMid === "audio") {
                let key = iceCandidate.protocol + "-" + iceCandidate.type + "-" + iceCandidate.port;
                this._remoteCandidateMap[key] = iceCandidate;
            }
            this._peerConn.addIceCandidate(iceCandidate).then(function () {
                log.debug(thiz._tag, "remote candidate message:{}", params);
            }).catch(function (e) {
                log.error(thiz._tag, "Failure during addIceCandidate: " + e.message);
                if (thiz._emitter) {
                    thiz._emitter.emit("error", ErrCode.ERR_ICE);
                }
            });
        }
    }

    setRemoteDescription(params) {
        let thiz = this;
        let sessionDescription = new RTCSessionDescription(params);
        this._peerConn.setRemoteDescription(sessionDescription).then(function () {
            log.debug(thiz._tag, "The description is successfully passed.");
            thiz._remoteParams = params;
            if ("offer" === params.type) {
                thiz.createAnswer();
            }
        }).catch(function (e) {
            log.error(thiz._tag, "Failure during setRemoteDescription: " + e.message);
            if (thiz._emitter) {
                thiz._emitter.emit("error", ErrCode.ERR_SDP);
            }
        })
    }

    createAnswer() {
        let thiz = this;
        this._peerConn.createAnswer().then(function (sessionDescription) {
            sessionDescription.sdp = SdpUtils.refineStereo(sessionDescription.sdp);
            return thiz._peerConn.setLocalDescription(sessionDescription);
        }).then(function () {
            if (thiz._emitter) {
                thiz._emitter.emit("description", thiz._peerConn.localDescription);
            }
        }).catch(function (event) {
            log.error(thiz._tag, "Failure during createAnswer: " + event.message);
            if (thiz._emitter) {
                thiz._emitter.emit("error", ErrCode.ERR_SDP);
            }
        })
    }

    addLocalStream(type, stream) {
        if (!!this._peerConn && !!stream) {
            if (type === "video") {
                this._cameraOn = true;
            }
            this._addTrack(type, stream);
            this._createOffer(type);
        }
    }

    cameraOff() {
        this._cameraOn = false;
        this._createOffer("video");
    }

    startStatistics() {
        if (this._statInterval === undefined) {
            this._bytesReceived = 0;
            this._framesReceived = 0;
            this._packetsReceived = 0;
            this._packetsLost = 0;
            this._jitterBufferDelay = 0;
            this._jitterBufferEmittedCount = 0;
            this._framesDecoded = 0;
            this._framesDropped = 0;
            this._lastTick = 0;
            this._lastRtt = 0;
            this._noRttCount = 0; //连续获取rtt失败的次数

            this._totalDecodeTime = 0;
            this._totalFramesDecoded = 0;
            this._totalInterFrameDelay = 0;
            this._nackCount = 0;
            this._qpSum = 0;
            this._decoderCodecId = undefined;
            this._trackId = undefined;

            this._rtpHasNoFramesInfoCount = 0;

            this._audioBytesReceived = 0;
            this._audioJitterBufferDelay = 0;
            this._audioJitterBufferEmittedCount = 0;

            this._cameraTotalEncodeTime = 0;
            this._cameraFramesEncoded = 0;
            this._cameraBytesSent = 0;
            this._cameraFramesSent = 0;
            this._cameraPacketesSent = 0;
            this._cameraTotalPacketSendDelay = 0;
            this._cameraNackCount = 0;
            this._cameraQpSum = 0;
            this._cameraEncoderCodecId = undefined;
            this._cameraSsrc = undefined;
            this._cameraTrackId = undefined;

            this._statsLocalCandidate = {};
            this._statsRemoteCandidate = {};
            this._candidatePairEmitted = false;

            this._statInterval = window.setInterval(this._onStatistics.bind(this), 1000);
        }
    }

    stopStatistics() {
        if (!!this._statInterval) {
            window.clearInterval(this._statInterval);
            delete this._statInterval;
        }
        delete this._statsCandidatePair;
        delete this._statsRemoteCandidate;
        delete this._statsLocalCandidate;
        delete this._candidatePairEmitted;
    }

    getPeerConnection() {
        return this._peerConn;
    }

    _createOffer(type) {
        let thiz = this;
        if (!!this._remoteParams) {
            let params = {};
            Object.assign(params, this._remoteParams);
            if (!!thiz._cameraOn && thiz._cameraCodecUseVP8) {
                params.sdp = SdpUtils.removeH264Sdp(params.sdp);
            }
            let sessionDescription = new RTCSessionDescription(params);
            this._peerConn.setRemoteDescription(sessionDescription)
                .then(function () {
                    return thiz._peerConn.createAnswer();
                })
                .then(function (sessionDescription) {
                    return thiz._peerConn.setLocalDescription(sessionDescription);
                })
                .then(function () {
                    if (thiz._emitter) {
                        let localDesc = new RTCSessionDescription({
                            type: "offer",
                            sdp: thiz._peerConn.localDescription.sdp
                        });
                        thiz._emitter.emit("description", localDesc);
                    }
                })
                .catch(function (e) {
                    log.error(thiz._tag, "Failure during createOffer: " + e.message);
                });
        }
    }

    _addTrack(type, stream) {
        const tracks = (type === "video") ? stream.getVideoTracks() : stream.getAudioTracks();
        if (tracks.length === 0) return;
        let sender = this._peerConn.getSenders().find(function(item) {
            return (!!(item.track) && item.track.kind === tracks[0].kind);
        });
        if (!!sender) {
            log.debug(this._tag, "replace local %s track", type);
            sender.replaceTrack(tracks[0]);
            return "replace";
        } else {
            log.debug(this._tag, "add local %s track", type);
            this._peerConn.addTrack(tracks[0]);
        }
    }

    _removeLocalStream() {
        try {
            let senders = this._peerConn.getSenders();
            let thiz = this;
            senders.forEach(function (sender) {
                thiz._peerConn.removeTrack(sender);
            });
        } catch (err) {
            log.error(this._tag, "catch removeTrack error:" + err);
        }
    }

    _onStatistics() {
        let thiz = this;
        if (this._peerConn && this._peerConn.connectionState === "connected") {
            this._peerConn.getStats(null).then(stats => {
                if (this._lastTick === 0) {
                    this._lastTick = Date.now();
                    return;
                }
                let now = Date.now();
                let interval = now - this._lastTick;
                this._lastTick = now;
                let statObj = {
                    rtt: undefined,
                    bitrate: 0,
                    fps: 0,
                    packetsLostRate: 0,
                    framesDroppedRate: 0,
                    width: 0,
                    height: 0,
                    bytesReceived: 0,
                    decodeDelayInMs: 0,
                    decoder: "",
                    codec: "",
                    interFrameDelayInMs: 0,
                    nackCount: 0,
                    nackCountPerSecond: 0,
                    qpSumInFramesDecodedPerSecond: 0,
                    jitterBufferDelayMs: 0
                };
                let audioObj = {
                    bitrate: 0,
                    bytesReceived: 0,
                    jitterBufferDelayMs: 0
                }
                let cameraObj = {
                    width: 0,
                    height: 0,
                    fps: 0,
                    bitrate: 0,
                    bytesSent: 0,
                    encodeDelayInMs: 0,
                    sendDelayInMs: 0,
                    roundTripTimeInMs: 0,
                    encoder: "",
                    codec: "",
                    nackCount: 0,
                    nackCountPerSecond: 0,
                    qpSumInFramesEncodedPerSecond: 0
                }
                if (LOGLEVEL < 2) {
                    statObj.jitterBufferDelayMs = 0;
                }
                let hasCamera = false;
                stats.forEach(report => {
                    if ('candidate-pair' === report.type && 'succeeded' === report.state) {
                        if (!thiz._statsCandidatePair) {
                            thiz._statsCandidatePair = report;
                        }
                        if (!!report['currentRoundTripTime']) {
                            statObj.rtt = Math.round(parseFloat(report['currentRoundTripTime']) * 1000);
                        }
                    } else if (!thiz._candidatePairEmitted && 'local-candidate' === report.type && !!thiz._statsLocalCandidate) {
                        thiz._statsLocalCandidate[report.candidateType] = report;
                    } else if (!thiz._candidatePairEmitted && 'remote-candidate' === report.type && !!thiz._statsRemoteCandidate) {
                        thiz._statsRemoteCandidate[report.candidateType] = report;
                    } else if ('inbound-rtp' === report.type && ('video' === report.kind || 'video' === report.mediaType)) {
                        if (!!report.packetsLost && !!report.packetsReceived) {
                            let lost = thiz._getSafeValue(report.packetsLost, thiz._packetsLost);
                            let total = thiz._getSafeValue((report.packetsReceived + report.packetsLost),
                                (thiz._packetsReceived + thiz._packetsLost));
                            statObj.packetsLostRate = total > 0 ? Math.round((lost / total) * 1000) / 1000 : 0;
                        }
                        thiz._packetsReceived = report.packetsReceived || 0;
                        thiz._packetsLost = report.packetsLost || 0;
                        statObj.packetsLostRate = statObj.packetsLostRate || 0;

                        let bytesRecv = thiz._getSafeValue(report.bytesReceived, thiz._bytesReceived);
                        statObj.bitrate = Math.round((bytesRecv * 8) / interval);
                        thiz._bytesReceived = statObj.bytesReceived = report.bytesReceived || 0;

                        let decodeTimePerSecond = thiz._getSafeValue(report.totalDecodeTime, thiz._totalDecodeTime);
                        let totalInterFrameDelayPerSecond = thiz._getSafeValue(report.totalInterFrameDelay, thiz._totalInterFrameDelay);
                        let framesDecodedPerSecond = thiz._getSafeValue(report.framesDecoded, thiz._totalFramesDecoded);
                        let qpSumPerSecond = thiz._getSafeValue(report.qpSum, thiz._qpSum);

                        statObj.decoder = report.decoderImplementation;
                        if (framesDecodedPerSecond > 0) {
                            statObj.decodeDelayInMs = thiz._toDecimal((decodeTimePerSecond * 1000) / framesDecodedPerSecond);
                            statObj.interFrameDelayInMs = thiz._toDecimal((totalInterFrameDelayPerSecond * 1000) / framesDecodedPerSecond);
                            statObj.qpSumInFramesDecodedPerSecond = thiz._toDecimal(qpSumPerSecond / framesDecodedPerSecond);
                        } else {
                            statObj.decodeDelayInMs = 0;
                            statObj.interFrameDelayInMs = 0;
                            statObj.qpSumInFramesDecodedPerSecond = 0;
                        }
                        statObj.nackCount = report.nackCount || 0;
                        statObj.nackCountPerSecond = thiz._getSafeValue(report.nackCount, thiz._nackCount);

                        thiz._totalDecodeTime = report.totalDecodeTime || 0;
                        thiz._totalFramesDecoded = report.framesDecoded || 0;
                        thiz._totalInterFrameDelay = report.totalInterFrameDelay || 0;
                        thiz._nackCount = report.nackCount || 0;
                        thiz._qpSum = report.qpSum || 0;
                        thiz._decoderCodecId = report.codecId;
                        thiz._trackId = report.trackId;
                        if (!!report.framesReceived) {
                            thiz._rtpHasNoFramesInfoCount = 0;
                            thiz._statisticsFps(report, statObj);
                        } else {
                            thiz._rtpHasNoFramesInfoCount++;
                        }
                    } else if ('track' === report.type && !!report.remoteSource && thiz._rtpHasNoFramesInfoCount >= 5 &&
                        ('video' === report.kind || (!!thiz._trackId && thiz._trackId === report.id)) && statObj.fps === 0) {
                        thiz._statisticsFps(report, statObj);
                    } else if ('inbound-rtp' === report.type && ('audio' === report.kind || 'audio' === report.mediaType)) {
                        let bytesRecv = thiz._getSafeValue(report.bytesReceived, thiz._audioBytesReceived);
                        audioObj.bitrate = Math.round((bytesRecv * 8) / interval);
                        thiz._audioBytesReceived = audioObj.bytesReceived = report.bytesReceived || 0;
                    } else if ('track' === report.type && 'audio' === report.kind && !!report.remoteSource) {
                        if (!!report['jitterBufferDelay'] && !!report['jitterBufferEmittedCount']) {
                            let count = thiz._getSafeValue(report['jitterBufferEmittedCount'], thiz._audioJitterBufferEmittedCount);
                            let delay = thiz._getSafeValue(report['jitterBufferDelay'], thiz._audioJitterBufferDelay);
                            if (count === 0) {
                                audioObj.jitterBufferDelayMs = 0;
                            } else {
                                audioObj.jitterBufferDelayMs = Math.round(delay * 1000 / count);
                            }
                            thiz._audioJitterBufferDelay = report['jitterBufferDelay'];
                            thiz._audioJitterBufferEmittedCount = report['jitterBufferEmittedCount'];
                        }
                    } else if (!!thiz._decoderCodecId && 'codec' === report.type && report.id === thiz._decoderCodecId) {
                        statObj.codec = report.mimeType;
                    } else if ('outbound-rtp' === report.type && ('video' === report.kind || 'video' === report.mediaType)) {
                        let bytesSentPerSecond = thiz._getSafeValue(report.bytesSent, thiz._cameraBytesSent);
                        cameraObj.bitrate = Math.round((bytesSentPerSecond * 8) / interval);

                        let encodeTimePerSecond = thiz._getSafeValue(report.totalEncodeTime, thiz._cameraTotalEncodeTime);
                        let framesEncodePerSecond = thiz._getSafeValue(report.framesEncoded, thiz._cameraFramesEncoded);
                        let totalPacketSendDelayPerSecond = thiz._getSafeValue(report.totalPacketSendDelay, thiz._cameraTotalPacketSendDelay);
                        let packetsSentPerSecond = thiz._getSafeValue(report.packetsSent, thiz._cameraPacketesSent);
                        let qpSumPerSecond = thiz._getSafeValue(report.qpSum, thiz._cameraQpSum);

                        cameraObj.encoder = report.encoderImplementation;
                        if (framesEncodePerSecond > 0) {
                            cameraObj.encodeDelayInMs = thiz._toDecimal((encodeTimePerSecond * 1000) / framesEncodePerSecond);
                            cameraObj.sendDelayInMs = thiz._toDecimal((totalPacketSendDelayPerSecond * 1000) / packetsSentPerSecond);
                            cameraObj.qpSumInFramesEncodedPerSecond = thiz._toDecimal(qpSumPerSecond / framesEncodePerSecond);
                        } else {
                            cameraObj.encodeDelayInMs = 0;
                            cameraObj.sendDelayInMs = 0;
                            cameraObj.qpSumInFramesEncodedPerSecond = 0;
                        }
                        cameraObj.nackCount = report.nackCount;
                        cameraObj.nackCountPerSecond = thiz._getSafeValue(report.nackCount, thiz._cameraNackCount);

                        thiz._cameraBytesSent = cameraObj.bytesSent = report.bytesSent || 0;
                        thiz._cameraTotalEncodeTime = report.totalEncodeTime || 0;
                        thiz._cameraFramesEncoded = report.framesEncoded || 0;
                        thiz._cameraTotalPacketSendDelay = report.totalPacketSendDelay || 0;
                        thiz._cameraPacketesSent = report.packetsSent || 0;
                        thiz._cameraQpSum = report.qpSum || 0;
                        thiz._cameraNackCount = report.nackCount || 0;
                        thiz._cameraEncoderCodecId = report.codecId;
                        thiz._cameraSsrc = report.ssrc;
                        thiz._cameraTrackId = report.trackId;
                    } else if ('track' === report.type && !report.remoteSource &&
                        ('video' === report.kind || (!!thiz._cameraTrackId && thiz._cameraTrackId === report.id))) {
                        cameraObj.width = report.frameWidth || 0;
                        cameraObj.height = report.frameHeight || 0;
                        if (cameraObj.width !== 0 && cameraObj.height !== 0 ) {
                            hasCamera = true;
                        }
                        if (!!report.framesSent) {
                            cameraObj.fps = thiz._getSafeValue(report.framesSent, thiz._cameraFramesSent);
                        }
                        thiz._cameraFramesSent = report.framesSent || 0;
                    } else if (!!thiz._cameraEncoderCodecId && 'codec' === report.type && report.id === thiz._cameraEncoderCodecId) {
                        cameraObj.codec = report.mimeType;
                    } else if (!!thiz._cameraSsrc && 'remote-inbound-rtp' === report.type && report.ssrc === thiz._cameraSsrc) {
                        cameraObj.roundTripTimeInMs = report.roundTripTime * 1000;
                    }
                });
                if (statObj.rtt === undefined) {
                    thiz._noRttCount++;
                    if (thiz._noRttCount < 3 && statObj.bitrate > 0 ) {
                        statObj.rtt = (thiz._lastRtt > 0) ? thiz._lastRtt : 0;
                    } else {
                        statObj.rtt = (thiz._lastRtt > 0) ? thiz._lastRtt + (thiz._noRttCount * 1000) : 0;
                    }

                } else {
                    thiz._lastRtt = statObj.rtt;
                    thiz._noRttCount = 0;
                }
                if (!thiz._candidatePairEmitted) {
                    thiz._emitCandidatePair();
                    thiz._candidatePairEmitted = true;
                }
                statObj.audio = audioObj;
                if (hasCamera) {
                    statObj.camera = cameraObj;
                }
                if (thiz._emitter) {
                    thiz._emitter.emit("statistics", statObj);
                }
            });
        }
    }

    _emitCandidatePair() {
        if (!!this._emitter && !!this._statsCandidatePair &&
            !!this._statsCandidatePair.localCandidateId &&
            !!this._statsCandidatePair.remoteCandidateId) {
            let clientAddr = this._getCandidateGrid("local", this._statsCandidatePair.localCandidateId);
            log.debug(this._tag, "local-candidate:" + clientAddr);
            let remoteAddr = this._getCandidateGrid("remote", this._statsCandidatePair.remoteCandidateId);
            log.debug(this._tag, "remote-candidate:" + remoteAddr);
            this._emitter.emit("candidatepair", {
                rtc_client_addr: clientAddr,
                rtc_server_addr: remoteAddr
            });
        }
    }

    _getCandidateGrid(side, selectId) {
        let statsCandidates = side === "local" ? this._statsLocalCandidate : this._statsRemoteCandidate;
        let iceCandidates = side === "local" ? this._localCandidateMap : this._remoteCandidateMap;
        let selectCandidate;
        for (let candidate of Object.values(statsCandidates)) {
            if (candidate.id === selectId) {
                selectCandidate = candidate;
                break;
            }
        }
        if (!selectCandidate) {
            log.error(this._tag, "no candidate select for " + side);
            return "unknown";
        }
        let type = selectCandidate.candidateType;
        let addrGrid = selectCandidate.protocol + "/";
        let firstItem = true;
        for (let i = this._getCandidateTypeIndex(type); i < this._candidataTypes.length; i++) {
            let statsCandidate = statsCandidates[this._candidataTypes[i]];
            let addr = this._getCandidateIpPort(statsCandidate, iceCandidates);
            if (!!addr) {
                if (!firstItem) {
                    addrGrid += "=>";
                }
                addrGrid += addr;
                firstItem = false;
            }
        }
        if (!!selectCandidate.networkType) {
            addrGrid += ("/" + selectCandidate.networkType)
        }
        return addrGrid;
    }

    _getCandidateIpPort(statsCandidate, iceCandidates) {
        if (!statsCandidate || !iceCandidates) return null;
        let addr;
        if (!!statsCandidate.address || !!statsCandidate.ip) {
            addr = ("[" + statsCandidate.candidateType + "]" + (statsCandidate.address || statsCandidate.ip) + ":" + statsCandidate.port);
        } else {
            let key = statsCandidate.protocol + "-" + statsCandidate.candidateType + "-" + statsCandidate.port;
            let iceCandidate = iceCandidates[key];
            if (!!iceCandidate) {
                addr = ("[" + iceCandidate.type + "]" + (iceCandidate.address || iceCandidate.ip) + ":" + iceCandidate.port);
            }
        }
        return addr;
    }

    _getCandidateTypeIndex(type) {
        for (let i = 0; i < this._candidataTypes.length; i++) {
            if (this._candidataTypes[i] === type) {
                return i;
            }
        }
        return this._candidataTypes.length - 1;
    }

    _statisticsFps(report, statObj) {
        if (!!report.framesReceived) {
            statObj.fps = this._getSafeValue(report.framesReceived, this._framesReceived);
        }
        this._framesReceived = report.framesReceived || 0;
        statObj.width = report.frameWidth || 0;
        statObj.height = report.frameHeight || 0;
        if (!!report['jitterBufferDelay'] && !!report['jitterBufferEmittedCount']) {
            let count = this._getSafeValue(report['jitterBufferEmittedCount'], this._jitterBufferEmittedCount);
            let delay = this._getSafeValue(report['jitterBufferDelay'], this._jitterBufferDelay);
            if (count === 0) {
                statObj.jitterBufferDelayMs = 0;
            } else {
                statObj.jitterBufferDelayMs = Math.round(delay * 1000 / count);
            }
            this._jitterBufferDelay = report['jitterBufferDelay'];
            this._jitterBufferEmittedCount = report['jitterBufferEmittedCount'];
        }
        statObj.framesReceived = report.framesReceived;
        statObj.framesDecoded = report.framesDecoded;
        statObj.framesDropped = report.framesDropped;
        if (!!report.framesDecoded && report.framesDropped !== undefined) {
            let decoded = this._getSafeValue(report.framesDecoded, this._framesDecoded);
            let dropped = this._getSafeValue(report.framesDropped, this._framesDropped);
            if (decoded > 0) {
                statObj.framesDroppedRate = Math.round((dropped / decoded) * 1000) / 1000;
            } else {
                statObj.framesDroppedRate = 0;
            }

            if (statObj.framesDroppedRate < 0) {
                statObj.framesDroppedRate = 0;
            }
        }
        this._framesDecoded = report.framesDecoded || 0;
        this._framesDropped = report.framesDropped || 0;
    }

    _addPCEventListeners() {
        this._addPCEventListener("track", this._onTrack.bind(this));
        this._addPCEventListener("icecandidate", this._onIceCandidate.bind(this));
        this._addPCEventListener("iceconnectionstatechange", this._onIceConnectionStateChange.bind(this));
        this._addPCEventListener("signalingstatechange", this._onSignalingStateChange.bind(this));
        this._addPCEventListener("connectionstatechange", this._onConnectionStateChange.bind(this));
        this._addPCEventListener("datachannel", this._onDatachannel.bind(this));
    }

    _addPCEventListener(evt, listener) {
        this._pcListeners[evt] = listener;
        this._peerConn.addEventListener(evt, listener);
    }

    _removePCEventListener(evt) {
        this._peerConn.removeEventListener(evt, this._pcListeners[evt]);
        delete this._pcListeners[evt];
    }

    _onTrack(event) {
        if (this._emitter) {
            this._emitter.emit("track", event);
        }
    }

    _onIceCandidate(event) {
        if (event.candidate) {
            if (event.candidate.sdpMid === "audio") {
                let key = event.candidate.protocol + "-" + event.candidate.type + "-" + event.candidate.port;
                this._localCandidateMap[key] = event.candidate;
            }
            if (this._emitter) {
                this._emitter.emit("icecandidate", event);
            }
        }
    }

    _onIceConnectionStateChange() {
        log.debug(this._tag, "[RTCPeerConnection] iceConnectionState: " + this._peerConn.iceConnectionState);
    }

    _onSignalingStateChange() {
        log.debug(this._tag, "[RTCPeerConnection] signalingState: " + this._peerConn.signalingState);
    }

    _onConnectionStateChange() {
        log.debug(this._tag, "[RTCPeerConnection] connectionState: " + this._peerConn.connectionState);
        if (this._emitter) {
            this._emitter.emit("connectionstatechange", this._peerConn.connectionState);
        }
    }

    _onDatachannel(event) {
        if (this._emitter) {
            this._emitter.emit("datachannel", event);
        }
    }

    _getSafeValue(a, b) {
        let value = (a < b) ? a : (a - b);
        return value || 0;
    }

    _toDecimal(value) {
        let val = Math.round(value * 100) / 100;
        return val || 0;
    }

}
