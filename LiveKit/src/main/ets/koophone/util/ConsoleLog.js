function print(level, tag, message, ...args) {
    const prefix = tag ? `[${tag}]` : '[legacy-koophone]';
    console[level](prefix, message, ...args);
}

export default {
    trace(tag, message, ...args) {
        print('debug', tag, message, ...args);
    },
    debug(tag, message, ...args) {
        print('debug', tag, message, ...args);
    },
    info(tag, message, ...args) {
        print('info', tag, message, ...args);
    },
    warn(tag, message, ...args) {
        print('warn', tag, message, ...args);
    },
    error(tag, message, ...args) {
        print('error', tag, message, ...args);
    }
};
