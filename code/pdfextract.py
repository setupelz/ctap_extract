# Extracts text data from all PDFs in /data and saves this as a structured
# json in /data/json. Errors are handled such that pdfs shifted to /error.

# Note that you must set your own Adobe PDF Services API credentials as follows -
# On MAC/linux: export PDF_SERVICES_CLIENT_ID='your_client_id'
# On MAC/linux: export PDF_SERVICES_CLIENT_SECRET='your_client_secret'
# On Windows: set PDF_SERVICES_CLIENT_ID=your_client_id
# On Windows: set PDF_SERVICES_CLIENT_SECRET=your_client_secret

# You will need to install pdfservices-extract-sdk

# This was written with the help of GitHub co-pilot and ChatGPT4o.
# To run, execute `python code/pdfextract.py` in the terminal from root.

import logging
import os
import shutil
from datetime import datetime
from adobe.pdfservices.operation.auth.service_principal_credentials import ServicePrincipalCredentials
from adobe.pdfservices.operation.exception.exceptions import ServiceApiException, ServiceUsageException, SdkException
from adobe.pdfservices.operation.pdf_services_media_type import PDFServicesMediaType
from adobe.pdfservices.operation.io.cloud_asset import CloudAsset
from adobe.pdfservices.operation.io.stream_asset import StreamAsset
from adobe.pdfservices.operation.pdf_services import PDFServices
from adobe.pdfservices.operation.pdfjobs.jobs.extract_pdf_job import ExtractPDFJob
from adobe.pdfservices.operation.pdfjobs.params.extract_pdf.extract_element_type import ExtractElementType
from adobe.pdfservices.operation.pdfjobs.params.extract_pdf.extract_pdf_params import ExtractPDFParams
from adobe.pdfservices.operation.pdfjobs.result.extract_pdf_result import ExtractPDFResult
from dotenv import load_dotenv

logging.basicConfig(level=logging.INFO)

# Load environment variables from .env file
load_dotenv()

class ExtractTextInfoFromPDF:
    def __init__(self, pdf_path, output_path):
        with open(pdf_path, 'rb') as file:
            input_stream = file.read()

        # Initial setup, create credentials instance
        credentials = ServicePrincipalCredentials(
            client_id=os.getenv('PDF_SERVICES_CLIENT_ID'),
            client_secret=os.getenv('PDF_SERVICES_CLIENT_SECRET')
        )

        # Creates a PDF Services instance
        pdf_services = PDFServices(credentials=credentials)

        # Creates an asset from the source file and upload
        input_asset = pdf_services.upload(input_stream=input_stream, mime_type=PDFServicesMediaType.PDF)

        # Create parameters for the job
        extract_pdf_params = ExtractPDFParams(
            elements_to_extract=[ExtractElementType.TEXT],
        )

        # Creates a new job instance
        extract_pdf_job = ExtractPDFJob(input_asset=input_asset, extract_pdf_params=extract_pdf_params)

        # Submit the job and gets the job result
        location = pdf_services.submit(extract_pdf_job)
        pdf_services_response = pdf_services.get_job_result(location, ExtractPDFResult)

        # Get content from the resulting asset
        result_asset: CloudAsset = pdf_services_response.get_result().get_resource()
        stream_asset: StreamAsset = pdf_services.get_content(result_asset)

        # Creates an output stream and copy stream asset's content to it
        with open(output_path, "wb") as file:
            file.write(stream_asset.get_input_stream())

    @staticmethod
    def create_output_file_path() -> str:
        now = datetime.now()
        time_stamp = now.strftime("%Y-%m-%dT%H-%M-%S")
        os.makedirs("output/ExtractTextInfoFromPDF", exist_ok=True)
        return f"output/ExtractTextInfoFromPDF/extract{time_stamp}.zip"

def main():
    pdf_root_directory = 'data/pdf'
    output_directory = 'data/json'
    error_directory = 'data/error'

    if not os.path.exists(output_directory):
        os.makedirs(output_directory)
    
    if not os.path.exists(error_directory):
        os.makedirs(error_directory)

    processed_files = [f.replace('.zip', '.pdf') for f in os.listdir(output_directory)]

    for country_folder in os.listdir(pdf_root_directory):
        country_path = os.path.join(pdf_root_directory, country_folder)
        if os.path.isdir(country_path):
            for pdf_file in os.listdir(country_path):
                if pdf_file.endswith('.pdf'):
                    if f"{country_folder}_{pdf_file}" in processed_files:
                        print(f"Skipping {pdf_file} as it was already processed")
                    else:
                        print(f"Processing {pdf_file}")
                        pdf_path = os.path.join(country_path, pdf_file)
                        json_filename = f"{country_folder}_{pdf_file.replace('.pdf', '.zip')}"
                        output_path = os.path.join(output_directory, json_filename)
                        try:
                            ExtractTextInfoFromPDF(pdf_path, output_path)
                            print(f"Extracted {pdf_file} to {output_path}")
                        except (ServiceApiException, ServiceUsageException, SdkException) as e:
                            print(f"Error processing {pdf_file}: {e}")
                            error_path = os.path.join(error_directory, pdf_file)
                            shutil.move(pdf_path, error_path)
                            print(f"Moved {pdf_file} to {error_path}")

if __name__ == "__main__":
    main()
