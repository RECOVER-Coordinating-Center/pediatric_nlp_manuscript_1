This repo contains files used for the publication "An NLP Pipeline for Identifying Pediatric Long COVID Symptoms and Functional Impacts in Freeform Clinical Notes: A RECOVER study."

# Pipeline files (Python)
Requirements: Pyspark, sparknlp_jsl, word2vec

The pipeline files are divided into four steps:
1. Text cleaning - Cleans the input text of things like unconverted code points and odd punctuation to make them more readable and more easily parsed.
2. Pyspark assertions - Runs the JSL pipeline on the input text. This produces a tokens file, which lists each found token for each note along with its associated NERs (symptom, disorder, etc), and an assertions file, which lists each found assertion chunk along with its assertion (present, absent, etc).
3. Regex - Performs a regex search to find phrases associated with each of 25 symptom clusters, then hooks together the associated tokens and, if they exist, JSL assertions. It also adds a regex assertion status.
4. Word2vec classification - Adds a third assertion status using word2vec, then performs a final adjustment of the JSL assertion status and adds a 'best guess' assertion status that uses all three of the JSL, regex, and word2vec assertion status to predict a final assertion. The word2vec model used is stored in w2vs3.bin 1 and 2 (divided due to size restrictions; must be combined into one file) and the assertion status prediction uses the vectors stored in the three .npy files.
The code used to train the w2v model is also included in w2v_training.ipynb.