# Where the touch playtest's driver finds the toolchain and the dev phone, and where it keeps its run files
# (screenshots, the touch log, requests): outside the repository, in the toolchain's tmp\play.
#   BARDROID_TOOLCHAIN   the toolchain folder (as scripts\env.bat: else ..\toolchain beside the checkout)
#   BARDROID_PLAY_DIR    the run files' folder (else <toolchain>\tmp\play)
#   BARDROID_DEVICE      the dev phone's adb serial (else the first USB entry of ..\phone-device.txt)
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
TOOLCHAIN = os.environ.get("BARDROID_TOOLCHAIN") or os.path.join(os.path.dirname(REPO), "toolchain")
WORK = os.environ.get("BARDROID_PLAY_DIR") or os.path.join(TOOLCHAIN, "tmp", "play")
os.makedirs(WORK, exist_ok=True)
ADB = os.path.join(TOOLCHAIN, "android-sdk", "platform-tools", "adb.exe")
os.environ["ANDROID_USER_HOME"] = os.path.join(TOOLCHAIN, "home", ".android")


def _device():
    if os.environ.get("BARDROID_DEVICE"):
        return os.environ["BARDROID_DEVICE"]
    listed = []
    f = os.path.join(os.path.dirname(TOOLCHAIN), "phone-device.txt")
    if os.path.exists(f):
        listed = [l.strip() for l in open(f) if l.strip() and not l.strip().startswith("#")]
    usb = [d for d in listed if ":" not in d]  # (the USB serial first: the Wi-Fi address is the backup)
    if usb or listed:
        return (usb or listed)[0]
    raise SystemExit("no dev phone: set BARDROID_DEVICE or list it in " + f)


DEV = _device()
