import os
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"
from pathlib import Path
from dotenv import load_dotenv
from langchain_community.document_loaders import PyPDFLoader, TextLoader, DirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.embeddings.fastembed import FastEmbedEmbeddings
from langchain_chroma import Chroma
import time

# Load environment variables (API keys)
load_dotenv()

DATA_DIR = str(Path(__file__).parent.parent / "data")
CHROMA_DB_DIR = str(Path(__file__).parent / "chroma_db")

def main():
    print("Starting data ingestion process...")
    
    # 1. Load Text files and PDFs (Only from the root of DATA_DIR to avoid reading textbooks in repos)
    print("Loading Text files and PDFs...")
    txt_loader = DirectoryLoader(DATA_DIR, glob="*.txt", loader_cls=TextLoader)
    txt_documents = txt_loader.load()
    print(f"Loaded {len(txt_documents)} Text documents.")

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
                    except Exception as e:
                        print(f"Warning: Failed to load {readme_path}: {e}")
                        
    print(f"Loaded {len(md_documents)} README documents from your projects.")

    # Combine all documents
    all_docs = txt_documents + pdf_documents + md_documents
    
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
    print("Generating embeddings (using fastembed) and storing in ChromaDB...")
    embeddings = FastEmbedEmbeddings(model_name="BAAI/bge-small-en-v1.5")
    
    # Process in batches to avoid timeouts
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
