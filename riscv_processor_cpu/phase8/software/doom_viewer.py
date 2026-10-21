"""Graphical receiver for the RV32 DOOM RVF1 framebuffer stream."""

import argparse
import queue
import sys
import threading
import time
import tkinter as tk
import zlib


MAGIC = b"RVF1"
WIDTH = 80
HEIGHT = 50
PIXELS = WIDTH * HEIGHT
PACKET_BYTES = 12 + PIXELS
RGB = tuple(
    bytes((((value >> 5) & 7) * 255 // 7,
           ((value >> 2) & 7) * 255 // 7,
           (value & 3) * 255 // 3))
    for value in range(256)
)


class FrameParser:
    def __init__(self):
        self.buffer = bytearray()
        self.bad_frames = 0

    def feed(self, chunk):
        self.buffer.extend(chunk)
        frames = []
        messages = []
        while True:
            start = self.buffer.find(MAGIC)
            if start < 0:
                count = max(0, len(self.buffer) - 3)
                messages.append(bytes(self.buffer[:count]))
                del self.buffer[:count]
                break
            if start:
                messages.append(bytes(self.buffer[:start]))
                del self.buffer[:start]
            if len(self.buffer) < PACKET_BYTES:
                break
            if self.buffer[4] != WIDTH or self.buffer[5] != HEIGHT:
                del self.buffer[0]
                continue
            pixels = bytes(self.buffer[12:PACKET_BYTES])
            crc = int.from_bytes(self.buffer[8:12], "little")
            if zlib.crc32(pixels) != crc:
                self.bad_frames += 1
                del self.buffer[0]
                continue
            sequence = int.from_bytes(self.buffer[6:8], "little")
            frames.append((sequence, pixels))
            del self.buffer[:PACKET_BYTES]
        text = b"".join(messages)
        text = bytes(b for b in text if b in (9, 10, 13) or 32 <= b <= 126)
        return frames, text.decode("ascii")


def self_test():
    pixels = bytes(i & 255 for i in range(PIXELS))
    packet = (MAGIC + bytes((WIDTH, HEIGHT)) + (0x1234).to_bytes(2, "little")
              + zlib.crc32(pixels).to_bytes(4, "little") + pixels)
    parser = FrameParser()
    frames = []
    text = ""
    for chunk in [b"RDD1:GO\r\n"] + [packet[i:i + 17]
                                       for i in range(0, len(packet), 17)]:
        found, message = parser.feed(chunk)
        frames.extend(found)
        text += message
    assert frames == [(0x1234, pixels)] and text == "RDD1:GO\r\n"
    damaged = bytearray(packet)
    damaged[22] ^= 1
    found, _ = parser.feed(damaged + packet)
    assert found == [(0x1234, pixels)] and parser.bad_frames == 1
    assert zlib.crc32(b"123456789") == 0xCBF43926
    print("DOOM Python viewer protocol tests passed.")


KEYS = {
    "Up": 0xAD, "w": 0xAD, "Down": 0xAF, "s": 0xAF,
    "Left": 0xAC, "a": 0xAC, "Right": 0xAE, "d": 0xAE,
    "Control_L": 0x9D, "Control_R": 0x9D, "f": 0x9D, "j": 0x9D,
    "space": 0xA2, "e": 0xA2,
    "Escape": 27, "q": 27, "Return": 13,
    "Shift_L": 0xB6, "Shift_R": 0xB6,
    "Tab": 9, "BackSpace": 127,
    **{str(n): ord(str(n)) for n in range(1, 8)},
    "y": ord("y"), "n": ord("n"), "m": ord("m"),
}


class Viewer:
    def __init__(self, port, baud, scale, auto_go):
        import serial

        self.serial = serial.Serial(port, baud, timeout=0.1, rtscts=False,
                                    dsrdtr=False)
        self.serial.dtr = False
        self.port = port
        self.scale = scale
        self.stop = threading.Event()
        self.frames = queue.Queue(maxsize=2)
        self.parser = FrameParser()
        self.sources = set()
        self.code_counts = {}
        self.pending_releases = {}
        self.picture = None
        self.image_id = None
        self.frame_count = 0
        self.fps_start = time.monotonic()

        self.root = tk.Tk()
        self.root.title(f"RV32 DOOM - {port} - waiting for frames")
        self.root.configure(background="black")
        self.root.resizable(False, False)
        self.canvas = tk.Canvas(self.root, width=WIDTH * scale,
                                height=HEIGHT * scale, background="black",
                                highlightthickness=0)
        self.canvas.pack()
        self.root.bind("<KeyPress>", self.key_down)
        self.root.bind("<KeyRelease>", self.key_up)
        self.root.bind("<FocusOut>", self.release_all)
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.root.focus_force()

        self.reader = threading.Thread(target=self.read_loop, daemon=True)
        self.reader.start()
        if auto_go:
            self.root.after(300, lambda: self.send(b"G"))
        self.root.after(30, self.update)

    def send(self, data):
        try:
            self.serial.write(data)
        except Exception as error:
            print(f"[viewer] UART write failed: {error}", file=sys.stderr)

    def read_loop(self):
        while not self.stop.is_set():
            try:
                chunk = self.serial.read(4096)
                if not chunk:
                    continue
                frames, message = self.parser.feed(chunk)
                if message:
                    print(message, end="", flush=True)
                for frame in frames:
                    if self.frames.full():
                        self.frames.get_nowait()
                    self.frames.put_nowait(frame)
            except Exception as error:
                if not self.stop.is_set():
                    print(f"[viewer] UART read failed: {error}", file=sys.stderr)
                return

    def update(self):
        latest = None
        while not self.frames.empty():
            latest = self.frames.get_nowait()
            self.frame_count += 1
        if latest is not None:
            sequence, pixels = latest
            ppm = b"P6\n80 50\n255\n" + b"".join(RGB[p] for p in pixels)
            original = tk.PhotoImage(data=ppm, format="PPM")
            self.picture = original.zoom(self.scale, self.scale)
            if self.image_id is None:
                self.image_id = self.canvas.create_image(0, 0, anchor="nw",
                                                         image=self.picture)
            else:
                self.canvas.itemconfigure(self.image_id, image=self.picture)
            elapsed = time.monotonic() - self.fps_start
            if elapsed >= 1:
                fps = self.frame_count / elapsed
                self.root.title(f"RV32 DOOM - {self.port} - {fps:.1f} FPS - "
                                f"frame {sequence} - CRC errors {self.parser.bad_frames}")
                self.frame_count = 0
                self.fps_start = time.monotonic()
        if not self.stop.is_set():
            self.root.after(30, self.update)

    @staticmethod
    def key_code(keysym):
        return KEYS.get(keysym, KEYS.get(keysym.lower()))

    def key_down(self, event):
        code = self.key_code(event.keysym)
        if code is None:
            return
        pending = self.pending_releases.pop(event.keysym, None)
        if pending is not None:
            self.root.after_cancel(pending)
            return "break"
        if event.keysym in self.sources:
            return "break"
        self.sources.add(event.keysym)
        count = self.code_counts.get(code, 0)
        self.code_counts[code] = count + 1
        if count == 0:
            self.send(bytes((code,)))
        return "break"

    def key_up(self, event):
        if event.keysym not in self.sources:
            return "break"
        self.pending_releases[event.keysym] = self.root.after(
            30, lambda key=event.keysym: self.finish_release(key))
        return "break"

    def finish_release(self, keysym):
        self.pending_releases.pop(keysym, None)
        if keysym not in self.sources:
            return
        self.sources.remove(keysym)
        code = self.key_code(keysym)
        count = self.code_counts[code] - 1
        if count:
            self.code_counts[code] = count
        else:
            del self.code_counts[code]
            self.send(bytes((0xF0, code)))

    def release_all(self, _event=None):
        for timer in self.pending_releases.values():
            self.root.after_cancel(timer)
        self.pending_releases.clear()
        for code in self.code_counts:
            self.send(bytes((0xF0, code)))
        self.sources.clear()
        self.code_counts.clear()

    def close(self):
        self.release_all()
        self.stop.set()
        self.serial.close()
        self.root.destroy()

    def run(self):
        try:
            self.root.mainloop()
        finally:
            if not self.stop.is_set():
                self.close()


def main():
    parser = argparse.ArgumentParser(description="RV32 DOOM binary framebuffer viewer")
    parser.add_argument("--port", default="COM4")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--scale", type=int, default=10)
    parser.add_argument("--no-go", action="store_true",
                        help="Attach to an already-running game")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not 1 <= args.scale <= 16:
        parser.error("--scale must be between 1 and 16")
    try:
        Viewer(args.port, args.baud, args.scale, not args.no_go).run()
    except Exception as error:
        parser.exit(1, f"Viewer failed: {error}. Close PuTTY on {args.port}.\n")


if __name__ == "__main__":
    main()
