class SocketShim {
    constructor() {
        this.connected = false;
        this.id = '';
    }

    on() {
    }

    off() {
    }

    emit() {
    }

    open() {
        this.connected = true;
    }

    close() {
        this.connected = false;
    }
}

export default {
    connect() {
        return new SocketShim();
    }
};
