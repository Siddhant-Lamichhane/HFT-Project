import serial
import struct
import time

class OrderBookSerial:
    START_BYTE = 0x7E

    TYPE_ADD    = 0b00
    TYPE_CANCEL = 0b01
    TYPE_EXEC   = 0b10

    def __init__(self, port='COM8', baudrate=115200, timeout=0.5):
        self.ser = serial.Serial(port, baudrate, timeout=timeout)

    def _build_frame(self, msg_type, order_id, price=0, size=0):
        payload = struct.pack('>HBB',
                              order_id & 0xFFFF,
                              price   & 0xFF,
                              size    & 0xFF)
        return bytes([self.START_BYTE, msg_type & 0x03]) + payload

    def send_add(self, order_id, price, size):
        self.ser.write(self._build_frame(self.TYPE_ADD, order_id, price, size))

    def send_cancel(self, order_id):
        self.ser.write(self._build_frame(self.TYPE_CANCEL, order_id, 0, 0))

    def send_exec(self, order_id, size):
        self.ser.write(self._build_frame(self.TYPE_EXEC, order_id, 0, size))

    def close(self):
        self.ser.close()


if __name__ == '__main__':
    ob = OrderBookSerial(port='COM8', baudrate=115200, timeout=0.5)
    try:
        # flush any old data
        ob.ser.reset_input_buffer()
        ob.ser.reset_output_buffer()

        # start the timer
        t0 = time.perf_counter()

        # 1) ADD
        ob.send_add(order_id=1, price=100, size=5)
        time.sleep(0.001)

        # 2) EXEC
        ob.send_exec(order_id=1, size=2)
        time.sleep(0.001)

        # 3) CANCEL
        ob.send_cancel(order_id=1)

        # now read back exactly 3 lines
        responses = []
        for _ in range(3):
            line = ob.ser.readline()
            if not line:
                print("Timeout waiting for FPGA response")
                break
            responses.append(line.decode('ascii', errors='ignore').strip())

        # stop the timer
        t1 = time.perf_counter()

        # print what FPGA said
        for i, resp in enumerate(responses, 1):
            print(f"FPGA said [{i}]: {resp}")

        # report round-trip latency
        elapsed_us = (t1 - t0) * 1e6
        print(f"3-frame round-trip took {elapsed_us:.1f} µs")

    finally:
        ob.close()
