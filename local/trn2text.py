#!/usr/bin/env python

# Copyright 2020 Kanari AI (Amir Hussein)
# Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)
import pdb
import numpy as np
import pandas as pd
import re
import string
import argparse
import sys
import os


_unicode = u"\u0622\u0624\u0626\u0628\u062a\u062c\u06af\u062e\u0630\u0632\u0634\u0636\u0638\u063a\u0640\u0642\u0644\u0646\u0648\u064a\u064c\u064e\u0650\u0652\u0670\u067e\u0686\u0621\u0623\u0625\u06a4\u0627\u0629\u062b\u062d\u062f\u0631\u0633\u0635\u0637\u0639\u0641\u0643\u0645\u0647\u0649\u064b\u064d\u064f\u0651\u0671"
_buckwalter = u"|&}btjGx*z$DZg_qlnwyNaio`PJ'><VApvHdrsSTEfkmhYFKu~{"

_backwardMap = {ord(a):b for a,b in zip(_buckwalter, _unicode)}

def fromBuckWalter(s):
    return s.translate(_backwardMap)


def read_tsv(data_file):
    text_data = list()
    infile = open(data_file, encoding='utf-8')
    for line in infile:
        if not line.strip():
            continue
        text= line.split('\t')
        text_data.append(text)
    
    return text_data


arabic_punctuations = '''`÷×؛<>_()*&^%][ـ،/:"؟.,'{}~¦+|!”…“–ـ'''


words_to_remove =['#غير_واضح', '#تلعثم', '#آ', '#أ', '#ال', '#بال', '#وال', ' #وب', '###تداخل', 'FRN','RFN',\
                  ' #سي', '#يي', '#هـ' , '#لل', '#بم', '#الش', '#آآ', ' #يت', '#وو', \
                  '#ومش', '#ول', '#وسي', '#غير_معروف','#العا','#مطا', '#محم' ,' #ماث','#متطو', ' #نشا', '#أأ', '#آآآ', ' #استج']

				  
def normalizeArabic(text):
    text = re.sub("[إأٱآا]", "ا", text)
    text = re.sub("ى", "ي", text)
    text = re.sub("ة", "ه", text)
    text = re.sub("ئ", "ء", text)
    text = re.sub("ؤ", "ء", text)
    return(text)
	
def remove_words(text):
    for word in words_to_remove:
        if word in text:
            text = text.replace(word, '')
    return text

def remove_hashes(text):
        return re.sub(r'#?', '', text)    

def remove_english_characters(text):
        return re.sub(r'[^\u0600-\u06FF0-9\s]+', '', text)
		
def remove_diacritics(text):
    return re.sub(r'[\u064B-\u0652\u06D4\u0670\u0674\u06D5-\u06ED]+', '', text)

def remove_punctuations(text):
    for p in arabic_punctuations:
        if p in text:
            text = text.replace(p, '')
    return text
    
def translate_numbers(text):
    
    return text.translate(trans_string)

def remove_repeating_char(text):
	return re.sub(r'\b(.)\1+\b', r'', text)
    
def remove_single_char_word(text):
	"""
	Remove single character word from text
	Example: I am in a home for 2 y years => am in home for 2 years 
	Args:
		text (str): text

	Returns:
		(str): text with single char removed
	"""
	words = text.split()
			
	filter_words = [word for word in words if len(word) > 1 or word.isnumeric()]
	return " ".join(filter_words)

		
def data_cleaning(text):
  text = remove_words(text)
  text = remove_punctuations(text)
  text = remove_diacritics(text)
  text = re.sub(r'#\w{1,2}\b', '', text)
  text = remove_hashes(text)
  text = normalizeArabic(text)
  #text = remove_repeating_char(text)
  text = remove_single_char_word(text)
  return text


def main():
	
	input_file = sys.argv[1] # input text file
	output_file=sys.argv[2] # output trn file
	data = read_tsv(input_file)
	new_data = []
	for i in range(len(data)):
		#pdb.set_trace()
		
		#tokens = data[i][0].strip().split()
		tokens = data[i][0].split('(')
		#tokens = [data[i][0][:idx].strip(), data[i][0][idx + 1 :].strip()[:-1]]
		#print(tokens)
		
		col2 = tokens[0].strip()
		col1 = tokens[1].strip()[:-1]
		
		new_data.append(col1 +" " +col2)
		
	df = pd.DataFrame(data=new_data)
	df.to_csv(output_file, sep = '\n', header=False, index=False)
		
if __name__ == "__main__":
    main()
