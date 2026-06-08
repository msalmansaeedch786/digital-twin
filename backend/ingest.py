import os
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"
from dotenv import load_dotenv
from langchain_community.document_loaders import PyPDFLoader, TextLoader, DirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma
import time

# Load environment variables (API keys)
load_dotenv()

DATA_DIR = "../data"
CHROMA_DB_DIR = "./chroma_db"

def main():
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("ERROR: GEMINI_API_KEY is not set in .env")
        return

    print("Starting data ingestion process...")
    
    # 1. Load PDFs (Only from the root of DATA_DIR to avoid reading textbooks in repos)
    print("Loading PDFs...")
    pdf_loader = DirectoryLoader(DATA_DIR, glob="*.pdf", loader_cls=PyPDFLoader)
    pdf_documents = pdf_loader.load()
    print(f"Loaded {len(pdf_documents)} pages from PDFs.")

    # 2. Load Markdown carefully (Only root READMEs to avoid API timeouts)
    print("Finding root README files for your projects...")
    md_documents = []
    
    repos_dir = os.path.join(DATA_DIR, "digital-twin-repos")
    if os.path.exists(repos_dir):
        for repo_name in os.listdir(repos_dir):
            repo_path = os.path.join(repos_dir, repo_name)
            if os.path.isdir(repo_path):
                # Look for README.md in the root of the repo
                readme_path = os.path.join(repo_path, "README.md")
                if not os.path.exists(readme_path):
                    readme_path = os.path.join(repo_path, "readme.md")
                if os.path.exists(readme_path):
                    try:
                        loader = TextLoader(readme_path)
                        md_documents.extend(loader.load())
                    except Exception:
                        pass
                        
    print(f"Loaded {len(md_documents)} README documents from your projects.")

    # Combine all documents
    all_docs = pdf_documents + md_documents
    
    if not all_docs:
        print("No documents found to ingest!")
        return

    # 3. Chunk the documents
    print("Chunking documents...")
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000,
        chunk_overlap=200,
        length_function=len
    )
    chunks = text_splitter.split_documents(all_docs)
    print(f"Created {len(chunks)} text chunks.")

    # 4. Create Embeddings and store in ChromaDB
    print("Generating embeddings (using local AI model) and storing in ChromaDB...")
    embeddings = HuggingFaceEmbeddings(
        model_name="all-MiniLM-L6-v2"
    )
    
    # Process in batches to avoid API rate limits and timeouts
    batch_size = 20
    vectorstore = None
    
    for i in range(0, len(chunks), batch_size):
        batch = chunks[i:i+batch_size]
        print(f"Processing batch {i//batch_size + 1}/{(len(chunks)-1)//batch_size + 1}...")
        
        if vectorstore is None:
            vectorstore = Chroma.from_documents(
                documents=batch,
                embedding=embeddings,
                persist_directory=CHROMA_DB_DIR
            )
        else:
            vectorstore.add_documents(batch)
            
        time.sleep(2) # Delay to respect free tier rate limits
    
    print(f"Successfully ingested data into ChromaDB at {CHROMA_DB_DIR}")

if __name__ == "__main__":
    main()
