# Sends extracted JSON data to OpenAI's GPT API to extract relevant text
# based on the keywords and prompt below. Note you must set your own OpenAI API
# credentials as follows -
# On MAC/linux: export OPENAI_API_KEY='your_openai_api_key'
# On Windows: set OPENAI_API_KEY=your_openai_api_key
# This was written with the help of GitHub co-pilot and ChatGPT4o.
# To run, execute `python code/pdfprocess.py` in the terminal from root.

import os
import json
from openai import OpenAI
import pandas as pd
import zipfile
import tiktoken

# Paths
zip_directory = 'data/json'
output_directory = 'output'

# OpenAI API key
openai_api_key = os.getenv('OPENAI_API_KEY')

if openai_api_key is None:
    raise ValueError("API key for OpenAI not found. Make sure it's set in the environment variables.")

# Set client for OpenAI API
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

# Function to read JSON data and extract Text keys with more than 50 characters
def read_and_filter_texts(jsontext):
    filtered_texts = []

    def _extract(obj):
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == "Text" and len(value) >= 50:
                    filtered_texts.append(value)
                else:
                    _extract(value)
        elif isinstance(obj, list):
            for item in obj:
                _extract(item)
    
    _extract(jsontext)
    return filtered_texts

# Function to split JSON data into chunks of approximately 200 tokens
def split_json_data(json_data, max_tokens=200):
    chunks = []
    current_chunk = []
    current_tokens = 0

    for item in json_data:  # Assuming the JSON data has an 'elements' key
        item_str = json.dumps(item)
        item_tokens = len(tokenizer.encode(item_str))
        if current_tokens + item_tokens > max_tokens:
            chunks.append(current_chunk)
            current_chunk = [item]
            current_tokens = item_tokens
        else:
            current_chunk.append(item)
            current_tokens += item_tokens

    if current_chunk:
        chunks.append(current_chunk)

    return chunks

# Function to code chunks of JSON text using OpenAI's GPT API
def query_json_with_openai(json_data_chunk):

    system_help = """
    You are an assistant helping a researcher extract relevant information from JSON text.
    Please assign one or more of the following codes to the JSON text. 
    Please be strict and only return codes that match the text exactly.
    Codes:
    '
    Scenario
    IPCC
    IEA
    Paris
    Offset
    Scope3
    '
    Here is a brief explanation of each of the codes:
    Scenario: Any mention of integrated assessment model scenarios.
    IPCC: Any mention of the Intergovernmental Panel on Climate Change.
    IEA: Any mention of the International Energy Agency or their scenarios, such as the net-zero scenario.
    Paris: Any mention of the Paris Agreement or specific temperatures of 1.5C or 2C.
    Offset: Specific carbon offsetting or negative emissions technologies (not decarbonisation).
    Scope3: Any mention of Scope 3 emissions or indirect emissions.
    """

    prompt = f"""
    If you don't find that any codes match, return "Not relevant" only.
    If you find codes that match, return this as follows:
    Code: [Codes that match]
    Here is the JSON text: {json.dumps(json_data_chunk)}
    """

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": system_help},
            {"role": "user", "content": prompt}
            ],
        max_tokens=500)

    return response.choices[0].message.content.strip()

# Function to save data to CSV
def save_data_to_csv(data, path, file_index):
    df = pd.DataFrame(data)
    file_path = os.path.join(path, f'extracted_data_{file_index}.csv')
    df.to_csv(file_path, index=False)

# Main function
def main():

    for zip_file in os.listdir(zip_directory):
        all_extracted_data = []
        if zip_file.endswith('.zip'):
            file_name = os.path.splitext(os.path.basename(zip_file))[0] 
            zip_path = os.path.join(zip_directory, zip_file)
            json_data = extract_json_from_zip(zip_path)
            json_data_text = read_and_filter_texts(json_data)            
            chunks = split_json_data(json_data_text)

            for chunk in chunks:

                relevant_sections = query_json_with_openai(chunk)

                if "Not relevant" in relevant_sections:
                    print("Chunk not relevant")

                if "Not relevant" not in relevant_sections:
                    lines = relevant_sections.split('\n')
                    code = "Unknown"

                    for line in lines:
                        if line.startswith("Code:"):
                            code = line.split("Code:")[1].strip()
                    
                    print(f"File: {file_name}, Code: {code}, Text: {chunk}")
                    all_extracted_data.append({
                        "File": file_name,
                        "Code": code,
                        "Text": chunk
                    })

            # Save structured csv
            save_data_to_csv(all_extracted_data, output_directory, file_name)

if __name__ == '__main__':
    main()