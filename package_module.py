import zipfile
import os
import shutil
import hashlib

out_zip = 'Galaxy_A05s_SuperFastCharge_v1.7.zip'

# Module files to sync and package
files_to_sync = [
    'action.sh',
    'config.prop',
    'customize.sh',
    'diag.sh',
    'module.prop',
    'pps_kp_override.ko',
    'service.sh',
]

dir_pairs = [
    ('webroot', 'module_package/webroot'),
    ('META-INF', 'module_package/META-INF'),
]

# Ensure module_package directory exists
os.makedirs('module_package', exist_ok=True)

# Sync root files to module_package
for f in files_to_sync:
    if os.path.exists(f):
        dst = os.path.join('module_package', f)
        if not os.path.exists(dst) or open(f, 'rb').read() != open(dst, 'rb').read():
            print(f"[*] Sincronizando {f} -> {dst}...")
            shutil.copy2(f, dst)

for src_d, dst_d in dir_pairs:
    if os.path.exists(src_d):
        os.makedirs(dst_d, exist_ok=True)
        for root, dirs, files in os.walk(src_d):
            for file in files:
                sf = os.path.join(root, file)
                rel = os.path.relpath(sf, src_d)
                df = os.path.join(dst_d, rel)
                os.makedirs(os.path.dirname(df), exist_ok=True)
                if not os.path.exists(df) or open(sf, 'rb').read() != open(df, 'rb').read():
                    print(f"[*] Sincronizando {sf} -> {df}...")
                    shutil.copy2(sf, df)

# Criar ZIP preservando permissoes executaveis do Linux (0755)
with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('module_package'):
        for file in sorted(files):
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, 'module_package').replace('\\', '/')
            
            with open(full_path, 'rb') as f:
                data = f.read()
                
            zinfo = zipfile.ZipInfo(rel_path)
            zinfo.compress_type = zipfile.ZIP_DEFLATED
            
            # Definir permissoes Unix (0755 para scripts / update-binary, 0644 para os demais)
            if rel_path.endswith('.sh') or 'update-binary' in rel_path:
                zinfo.external_attr = (0o755 | 0o100000) << 16  # -rwxr-xr-x
            else:
                zinfo.external_attr = (0o644 | 0o100000) << 16  # -rw-r--r--
                
            z.writestr(zinfo, data)

print(f"[+] Modulo empacotado com sucesso em '{out_zip}' ({os.path.getsize(out_zip)} bytes)")
with zipfile.ZipFile(out_zip, 'r') as z:
    for f in z.infolist():
        mode = oct(f.external_attr >> 16)
        print(f"  {f.filename:45} {f.file_size:>9} bytes  mode:{mode}")
