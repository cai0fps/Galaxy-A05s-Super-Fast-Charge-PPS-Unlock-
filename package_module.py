import zipfile
import os

out_zip = 'Galaxy_A05s_SuperFastCharge_v3.4.zip'
src_dir = 'module_package'

# Ensure pps_kp_override.ko is in module_package
ko_src = 'pps_kprobe_override.ko'
ko_dst = os.path.join(src_dir, 'pps_kp_override.ko')
if not os.path.exists(ko_dst) or os.path.getsize(ko_dst) != os.path.getsize(ko_src):
    import shutil
    shutil.copyfile(ko_src, ko_dst)

with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src_dir):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, src_dir).replace('\\', '/')
            z.write(full_path, rel_path)

print(f"Packaged {out_zip} from {src_dir} successfully! Size: {os.path.getsize(out_zip)} bytes")
with zipfile.ZipFile(out_zip, 'r') as z:
    for f in z.infolist():
        print(f"  {f.filename:45} {f.file_size} bytes")
