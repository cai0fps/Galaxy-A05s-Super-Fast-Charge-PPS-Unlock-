import zipfile
import os
import shutil
import hashlib

out_zip = 'Galaxy_A05s_SuperFastCharge_v1.6.zip'
src_dir = 'module_package'

def file_hash(path):
    if not os.path.exists(path):
        return None
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

# Ensure pps_kp_override.ko is up to date in module_package
ko_src = 'pps_kprobe_override.ko'
ko_dst = os.path.join(src_dir, 'pps_kp_override.ko')

if os.path.exists(ko_src):
    if not os.path.exists(ko_dst) or file_hash(ko_src) != file_hash(ko_dst):
        print(f"[*] Sincronizando {ko_src} -> {ko_dst} (conteudo modificado)...")
        shutil.copyfile(ko_src, ko_dst)
elif not os.path.exists(ko_dst):
    raise FileNotFoundError(f"Erro: Arquivo do driver '{ko_src}' nem '{ko_dst}' foram encontrados!")

# Criar ZIP preservando permissoes executaveis do Linux (0755)
with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src_dir):
        for file in sorted(files):
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, src_dir).replace('\\', '/')
            
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
