export const ERR_SIGNAL_CONNECT_TIMEOUT = 1002;
export const ERR_TOKEN = 1003;
export const ERR_SIGNAL_EXIT_ROOM = 1004;
export const ERR_SIGNAL_MESSAGE_TIMEOUT = 1005;
export const ERR_START_TIMEOUT = 1006;
export const ERR_UNSUPPORT_BROWSER = 1007;
export const ERR_ICE = 1008;
export const ERR_SDP = 1009;

export function getCode(code) {
    const parsed = Number(code);
    return Number.isNaN(parsed) ? undefined : parsed;
}
