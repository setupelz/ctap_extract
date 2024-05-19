# Extracts text data from all PDFs in /data and saves this as a structured
# json in /data/json. Note that you must set your own Adobe PDF Services API 
# credentials as follows -
# On MAC/linux: export PDF_SERVICES_CLIENT_ID='your_client_id'
# On MAC/linux: export PDF_SERVICES_CLIENT_SECRET='your_client_secret'
# On Windows: set PDF_SERVICES_CLIENT_ID=your_client_id
# On Windows: set PDF_SERVICES_CLIENT_SECRET=your_client_secret
# This was written with the help of GitHub co-pilot and ChatGPT4o.
# To run, execute `python code/pdfextract.py` in the terminal from root.

import logging
import os

from adobe.pdfservices.operation.auth.credentials import Credentials
from adobe.pdfservices.operation.exception.exceptions import ServiceApiException, ServiceUsageException, SdkException
from adobe.pdfservices.operation.pdfops.options.extractpdf.extract_pdf_options import ExtractPDFOptions
from adobe.pdfservices.operation.pdfops.options.extractpdf.extract_element_type import ExtractElementType
from adobe.pdfservices.operation.execution_context import ExecutionContext
from adobe.pdfservices.operation.io.file_ref import FileRef
from adobe.pdfservices.operation.pdfops.extract_pdf_operation import ExtractPDFOperation

logging.basicConfig(level=os.environ.get("LOGLEVEL", "INFO"))

# Paths
pdf_root_directory = 'data/pdf'
output_directory = 'data/json'

# Function to extract text from PDF
def extract_text_from_pdf(pdf_path, output_path):
    try:
        # Initial setup, create credentials instance.
        credentials = Credentials.service_principal_credentials_builder() \
            .with_client_id(os.getenv('PDF_SERVICES_CLIENT_ID')) \
            .with_client_secret(os.getenv('PDF_SERVICES_CLIENT_SECRET')) \
            .build()

        # Create an ExecutionContext using credentials and create a new operation instance.
        execution_context = ExecutionContext.create(credentials)
        extract_pdf_operation = ExtractPDFOperation.create_new()

        # Set operation input from a source file.
        source = FileRef.create_from_local_file(pdf_path)
        extract_pdf_operation.set_input(source)

        # Build ExtractPDF options and set them into the operation
        extract_pdf_options = ExtractPDFOptions.builder() \
            .with_element_to_extract(ExtractElementType.TEXT) \
            .build()
        extract_pdf_operation.set_options(extract_pdf_options)

        # Execute the operation.
        result = extract_pdf_operation.execute(execution_context)

        # Save the result to the specified location.
        result.save_as(output_path)
    except (ServiceApiException, ServiceUsageException, SdkException):
        logging.exception(f"Exception encountered while executing operation for file {pdf_path}")

# Main function
def main():
    if not os.path.exists(output_directory):
        os.makedirs(output_directory)

    for country_folder in os.listdir(pdf_root_directory):
        country_path = os.path.join(pdf_root_directory, country_folder)
        if os.path.isdir(country_path):
            for pdf_file in os.listdir(country_path):
                if pdf_file.endswith('.pdf'):
                    pdf_path = os.path.join(country_path, pdf_file)
                    json_filename = f"{country_folder}_{pdf_file.replace('.pdf', '.zip')}"
                    output_path = os.path.join(output_directory, json_filename)
                    extract_text_from_pdf(pdf_path, output_path)
                    print(f"Extracted {pdf_file} to {output_path}")

if __name__ == '__main__':
    main()
