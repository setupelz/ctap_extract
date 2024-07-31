# Sends extracted JSON data to OpenAI's GPT API to extract relevant text
# based on the keywords and prompt below. Note you must set your own OpenAI API
# credentials as follows -
# On MAC/linux: export OPENAI_API_KEY='your_openai_api_key'
# On Windows: set OPENAI_API_KEY=your_openai_api_key
# This was written with the help of GitHub co-pilot and ChatGPT4o.
# To run, execute `python code/pdfprocess.py` in the terminal from root.

import os
import json
import re
from openai import OpenAI
import pandas as pd
import zipfile
import tiktoken
import hashlib
import argparse

# Paths
zip_directory = 'data/json'
output_directory = 'output'

# OpenAI API key
openai_api_key = os.getenv('OPENAI_API_KEY')
if openai_api_key is None:
    raise ValueError("API key for OpenAI not found. Make sure it's set in the environment variables.")
client = OpenAI(api_key=openai_api_key)

# Initialize the tokenizer
tokenizer = tiktoken.get_encoding("cl100k_base")

# Function to extract JSON files from zip archives
def extract_json_from_zip(zip_path):
    json_data_list = []
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        for file in zip_ref.namelist():
            if file.endswith('.json'):
                with zip_ref.open(file) as json_file:
                    data = json.load(json_file)
                    json_data_list.append(data)
    return json_data_list

# Function to generate a unique ID based on a base string and a page number
def generate_unique_id(base_str, page_number, text):
    return hashlib.md5(f"{base_str}_{page_number}_{text}".encode()).hexdigest()

# Function to clean text by removing special characters except normal punctuation
def clean_text(text):
    return re.sub(r'[^a-zA-Z0-9\s.,!?()[\]{}<>-]', '', text)

# Function to read JSON data and extract Text keys with more than 50 characters
def read_and_filter_texts(jsontext):
    filtered_texts = []

    def _extract(obj, current_page=None):
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == "Page":
                    current_page = value
                if key == "Text" and len(value) >= 50:
                    cleaned_value = clean_text(value)
                    if filtered_texts and not filtered_texts[-1]["Text"].strip()[-1] in '.!?':
                        filtered_texts[-1]["Text"] += " " + cleaned_value
                    else:
                        filtered_texts.append({"Text": cleaned_value, "Page": current_page})
                else:
                    _extract(value, current_page)
        elif isinstance(obj, list):
            for item in obj:
                _extract(item, current_page)

    _extract(jsontext)
    return filtered_texts

# Function to split JSON data into chunks of approximately 1000 tokens
def split_json_data(json_data, max_tokens=1000, zip_file="default_zip"):
    chunks = []

    for item in json_data:
        item_str = json.dumps(item)
        item_tokens = len(tokenizer.encode(item_str))
        page_number = item.get("Page", 0)
        
        if item_tokens > max_tokens:
            current_chunk = []
            current_tokens = 0
            for char in item_str:
                current_tokens += 1
                current_chunk.append(char)
                if current_tokens >= max_tokens:
                    chunk_str = "".join(current_chunk)
                    chunk_id = generate_unique_id(zip_file, page_number, item_str)
                    chunks.append({"Chunk": chunk_str, "Page": page_number, "ID": chunk_id})
                    current_chunk = []
                    current_tokens = 0
            if current_chunk:
                chunk_str = "".join(current_chunk)
                chunk_id = generate_unique_id(zip_file, page_number, item_str)
                chunks.append({"Chunk": chunk_str, "Page": page_number, "ID": chunk_id})
        else:
            chunk_id = generate_unique_id(zip_file, page_number, item_str)
            chunks.append({"Chunk": item_str, "Page": page_number, "ID": chunk_id})
    
    return chunks

# Function to query OpenAI's API
def query_json_with_openai(json_data_chunk):
    """
    Code chunks of JSON text using OpenAI's GPT-4 API.

    Args:
        json_data_chunk (dict): A chunk of JSON data to be coded.

    Returns:
        str: The codes assigned to the text or "Not relevant".
    """

    system_help = """
    You are a helpful assistant classifying textual elements, focusing entirely on discussions of scenarios. 

    In this context, scenarios are projections of future: emissions, commodity use, energy use, energy consumption, prices, demand, climate or climate impacts.

    Only consider textual elements that refer to a comparison of scenarios in this context, or the alignment of scenarios with specific targets in this context.

    If the textual element does not refer to a comparison of scenarios in this context as described above, please return "Not relevant".

    Please classify each text snippet with the appropriate codes. Consider related terms and synonyms to ensure accurate coding without creating false positives.

    Use the following single-letter codes and their explanations:

    a: Text discussing alignment, comparison, contrast, or consistency of a scenario with scenarios from the Intergovernmental Panel on Climate Change (IPCC) and their reports.

    b: Text discussing alignment, comparison, contrast, or consistency of a scenario with scenarios from the International Energy Agency (IEA) and their reports.

    c: Text discussing alignment, comparison, contrast, or consistency of a scenario with Network for Greening the Financial System (NGFS) scenarios.

    d: Text discussing use of a scenario from any organization other than IPCC, IEA, and NGFS.

    e: Text discussing alignment, comparison, contrast, or consistency of a scenario with the Paris Agreement's 1.5°C or well-below 2°C targets.

    f: Text discussing alignment, comparison, contrast, or consistency of a scenario with a 2°C warming or 2°C pathway scenario (not well-below 2°C).

    g: Text discussing alignment, comparison, contrast, or consistency of a scenario with the Representative Concentration Pathways (RCP).

    h: Text discussing alignment, comparison, contrast, or consistency of a scenario with a C1a, C1, C2, C3, or C4 category scenario.

    i: Text discussing climate impact projections, climate risks, climate-related impacts or climate-related risks in a given scenario.

    j: Text discussing resilience, adaptation, or adaptive capacity of a business strategy, expected demand of commodities, or scenario in relation to climate change scenarios.

    k: Text comparing Scope 3 or 'value chain' emissions in the context of scenarios.

    l: Text comparing the use of offsets, carbon offsetting, carbon credits, carbon neutral or negative emissions technologies such as carbon capture and storage (CCS) in the context of scenarios.

    m: Text comparing the use of Bioenergy with Carbon Capture and Storage (BECCS) or related negative emissions technologies in the context of scenarios.

    n: Text comparing the use of Direct Air Capture (DAC), atmospheric carbon removal, or related negative emissions technologies in the context of scenarios.
    """

    prompt = f"""
    Here is the text: {json.dumps(json_data_chunk)}
    If you don't find that any codes match, return "Not relevant".
    If you find codes that match, return this as follows:
    Codes: []
    Always report a code. If you find multiple codes, separate them with commas in square brackets. If you find no codes, return "Not relevant".
    """

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": system_help},
            {"role": "user", "content": prompt}
            ],
            max_tokens=1000,
            n=1,
            stop=None,
            temperature=0.1)
    
    result = response.choices[0].message.content.strip()
    return result

# Function to save data to CSV
def save_data_to_csv(data, path, file_index):
    df = pd.DataFrame(data)
    file_path = os.path.join(path, f'extracted_data_{file_index}.csv')
    df.to_csv(file_path, index=False)

# Define main function
def main(max_files_to_process=None):
    # Gather all .csv filenames that were already processed in output_directory
    processed_files = [f.replace('.csv', '.zip') for f in os.listdir(output_directory)]

    print(processed_files)

    processed_count = 0

    for zip_file in os.listdir(zip_directory):
        if max_files_to_process is not None and processed_count >= max_files_to_process:
            print("Reached the maximum number of files to process.")
            break

        # Check if the zip_file is in processed_files
        if f"extracted_data_{zip_file}" in processed_files:
            print(f"Skipping {zip_file} as it was already processed")
        else: 
            print(f"Processing {zip_file}")

            all_extracted_data = []
            if zip_file.endswith('.zip'):
                file_name = os.path.splitext(os.path.basename(zip_file))[0] 
                zip_path = os.path.join(zip_directory, zip_file)
                json_data = extract_json_from_zip(zip_path)
                json_data_text = read_and_filter_texts(json_data)            
                chunks = split_json_data(json_data_text, zip_file=zip_file)

                for chunk in chunks:
                    try:
                        chunk_data = json.loads(chunk["Chunk"])  # Parse the JSON string to a dictionary
                    except json.JSONDecodeError as e:
                        print(f"Error decoding chunk: {e}")
                        continue

                    relevant_sections = query_json_with_openai(chunk_data["Text"])

                    if "Not relevant" in relevant_sections:
                        print("Chunk not relevant")
                    else:
                        lines = relevant_sections.split('\n')
                        code = "Unknown"

                        for line in lines:
                            if line.startswith("Codes:"):
                                code = line.split("Codes:")[1].strip()

                        print(f"File: {file_name}, Codes: {code}, Page: {chunk['Page']}, ID: {chunk['ID']}, Text: {chunk_data['Text']}")
                        all_extracted_data.append({
                            "File": file_name,
                            "Codes": code,
                            "Page": chunk["Page"],
                            "ID": chunk["ID"],
                            "Text": chunk_data["Text"]
                        })

                # Save structured csv
                save_data_to_csv(all_extracted_data, output_directory, file_name)
                processed_count += 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process PDF files and extract relevant data.')
    parser.add_argument('--max_files', type=int, default=None, help='Maximum number of files to process (to limit costs)')
    args = parser.parse_args()

    main(max_files_to_process=args.max_files)
