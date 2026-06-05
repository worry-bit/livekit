export default {
    supportRTCPeerConnection() {
        return typeof RTCPeerConnection !== 'undefined';
    }
};
