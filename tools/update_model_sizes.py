import os
import json
import tempfile
import requests
import shutil
import zipfile
import tarfile

MODEL_FILE = "ResourceDownloader/ResourceDownloader/models.json"

def download_file(url, download_path):
    local_filename = os.path.join(download_path, url.split('/')[-1].split("?")[0])
    with requests.get(url, stream=True) as r:
        r.raise_for_status()
        with open(local_filename, 'wb') as f:
            shutil.copyfileobj(r.raw, f)
    return local_filename

def extract_archive(archive_path, extract_to):
    if zipfile.is_zipfile(archive_path):
        with zipfile.ZipFile(archive_path, 'r') as zip_ref:
            zip_ref.extractall(extract_to)
    elif tarfile.is_tarfile(archive_path):
        with tarfile.open(archive_path, 'r:*') as tar_ref:
            tar_ref.extractall(extract_to)
    else:
        raise ValueError(f"Unsupported archive format: {archive_path}")

def get_directory_size(path):
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if os.path.isfile(fp):
                total_size += os.path.getsize(fp)
    return total_size

def get_file_size(file_path):
    if os.path.isfile(file_path):
        return os.path.getsize(file_path)
    else:
        raise ValueError(f"File not found: {file_path}")

def process_entry(entry, tmpdir):
    for file in entry.get("files", []):
        print(f"\nProcessing: {file['url']}")
        
        try:
            archive = download_file(file["url"], tmpdir)
            
            download_size = get_file_size(archive)
            extracted_size = download_size # fallback if it is not an archive
            
            try:
                extract_path = os.path.join(tmpdir, os.path.basename(archive) + "_extracted")
                os.makedirs(extract_path, exist_ok=True)

                extract_archive(archive, extract_path)
                extracted_size = get_directory_size(extract_path)
            except Exception as e:
                pass
            
            print(f"Downloaded size: {download_size}")
            print(f"Extracted size: {extracted_size}")
        
            file["dsize"] = download_size
            file["esize"] = extracted_size
            
        except Exception as e:
            print(f"Failed to process {file['url']}: {e}")

    for child in entry.get("children", []):
        process_entry(child, tmpdir)


with open(MODEL_FILE, "r") as f:
    data = json.load(f)

with tempfile.TemporaryDirectory() as tmpdir:
    for entry in data:
        process_entry(entry, tmpdir)

with open(MODEL_FILE, "w") as f:
    json.dump(data, f, indent=2)

print("\nModel sizes updated successfully.")
