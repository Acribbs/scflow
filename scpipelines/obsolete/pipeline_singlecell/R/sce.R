#!/usr/bin/env Rscript

library("tidyverse")
library("SingleCellExperiment")
library("optparse")
library('biomaRt')
library("Matrix")
library("tximport")

option_list = list(
  make_option(c("-w", "--workingdir"), type="character", default=NULL, 
              help="working directory", metavar="character"),
  make_option(c("-i", "--input"), type="character", default="salmon.dir/alevin/quants_mat.gz", 
              help="input file (quants_mat.gz/GCcoordmatrix.mtx path) [default= %default]", metavar="character"),
  make_option(c("-o", "--out"), type="character", default="sce.rds", 
              help="output file name [default= %default]", metavar="character"),
  make_option(c("-s", "--species"), type="character", default="human", 
              help="Species, human or mouse [default = %default]", metavar="character"),
  make_option(c("-g", "--genesymbol"), type="integer", default="0", 
              help="Logical. Whether to use gene names/symbols instead of ensembl IDs in SCE object  [default = %default]", metavar="integer"),
  make_option(c("-p", "--pseudoaligner"), type="character", default="alevin", 
              help="Pseudoaligner used, kallisto or alevin [default = %default]", metavar="character"),
  make_option(c("-d", "--downsample"), type="integer", default=NULL, 
              help="Number of cells to randomly downsample to [default = %default]", metavar="character")
  ); 


opt_parser = OptionParser(option_list=option_list);
opt = parse_args(opt_parser);

wd = opt$workingdir

setwd(wd)
out <- opt$out
input <- opt$input
pseudo <- opt$pseudoaligner 
downsample <- opt$downsample



readAlevin <- function(files){
	txi <- tximport(files, type= "alevin")
	mat <- txi$counts  

if(!is.null(downsample)){

	 downsample_list <- sort(sample(colanmes(mat), downsample, replace = F))

 	 mat <- mat[,downsample_list]
}

	return(mat)
}

## Kallisto BUS matrix

readBus <- function(files) {
  dir <- dirname(files)
  barcode.file <- file.path(dir, "GCmatrix.cells")
  fgene.file <- file.path(dir, "GCmatrix.genes")
  # Using sparse matrix
  matrix.file <- file.path(dir, "output.bus_GCcoordmatrix.mtx")

  for (f in c(barcode.file, gene.file, matrix.file)) {
    if (!file.exists(f)) {
      stop("expecting 'files' to point to 'output.bus.mat.gz' file in a directory 'kallisto/<Sample_Name>'
           also containing 'GCmatrix.cells' and 'GCmatrix.genes'.
           please re-run kallisto and bustools")
    }
  }
  
  sparse_in <- readMM(matrix.file)
  mat <- as.matrix(sparse_in)
  
  cell.names <- readLines(barcode.file)
  gene.names <- readLines(gene.file)
  num.cells <- length(cell.names)
  num.genes <- length(gene.names)
  rownames(mat) <- gene.names
  colnames(mat) <- cell.names
  
  return(mat)
  }

if(pseudo == "alevin"){
  mat <- readAlevin(input)
} else if(pseudo == "kallisto"){
  mat <- readBus(input)
} else{
  stop("expecting kallisto or alevin.")
}


# Convert to gene names 
gene_name <- as.integer(opt$genesymbol)
if(gene_name){
  df <- as.data.frame(mat)
  species <- opt$species
  if(species == "human"){
    emsembl_species <- "hsapiens_gene_ensembl"
    symbol <- "hgnc_symbol"
  }
  if(species == "mouse"){
    emsembl_species <- "mmusculus_gene_ensembl"
    symbol <- "mgi_symbol"
  }
  mart <- useDataset(emsembl_species, useMart("ensembl", host="uswest.ensembl.org", ensemblRedirect = FALSE))
  genes <- rownames(df)
  G_list <- getBM(filters= "ensembl_gene_id", attributes=c("ensembl_gene_id",symbol),values=genes,mart= mart)
  df <- merge(as.data.frame(df),G_list,by.x="row.names",by.y="ensembl_gene_id")
  df$Row.names <- NULL
  rownames(df) <- make.unique(df[[symbol]])
  df[[symbol]] <- NULL
  mat <- as.matrix(df)
}

v <- log2(mat + 1)
sce <- SingleCellExperiment(assays = list(counts = mat, logcounts = v))
saveRDS(object = sce, file = out)

