#! /usr/bin/env python3
import re
import sys

# Tool to Automatically Construct the Cpp-Model-Wrapper from the Xspec lmodel.dat file
# - models are separated by an empty line
# - for <model_name> the C-function has to be called c_<local_model_prefix><model_name>

local_model_prefix = "lmod"

header = """/*
   *** AUTOMATICALLY CREATED: DO NOT EDIT THIS FILE ***   

   This file is part of the RELXILL model code.

   RELXILL is free software: you can redistribute it and/or modify it
   under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   any later version.

   RELXILL is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
   GNU General Public License for more details.
   For a copy of the GNU General Public License see
   <http://www.gnu.org/licenses/>.

    Copyright 2020 Thomas Dauser, Remeis Observatory & ECAP
       
    *** AUTOMATICALLY CREATED: DO NOT EDIT THIS FILE ***       
*/

#include "cppmodels.h"
#include "cppparameters.h"
"""


def remove_empty_strings(list_strings):
    for string in list_strings:
        if len(string) <= 1:
            list_strings.remove(string)

    return list_strings


def read_file_in_chunks(input_file):
    empty_line = '\n\n'
    with open(input_file, 'r') as reader:
        split_file = reader.read().split(empty_line)

    return remove_empty_strings(split_file)


def parse_model_name(model_definition):
    first_line = model_definition.split('\n')[0]

    res = re.match(rf'.*c_{local_model_prefix}(\w+).*', first_line)
    if res is not None:
        return res.groups()[0]
    else:
        return None


#
# parse the lmodel.dat file to get all defined local model names
# input:  filename for the model definition (lmodel.dat file)
# return: list of model names
def get_model_names(lmodeldat_file):
    model_list = []

    for single_model_definition in read_file_in_chunks(lmodeldat_file):
        model_name = parse_model_name(single_model_definition)
        if len(model_name) > 0:
            model_list.append(model_name)
            print("    - " + model_name)
        else:
            print(" *** error ***: could not parse the following model definition")
            print(single_model_definition)

    return model_list


def get_wrapper_lmod(local_model_name):
    parameter_list = "const double *energy, int Nflux, const double *parameter, int spectrum, double *flux, double *fluxError, const char *init"
    function_call = "xspec_C_wrapper_eval_model(ModelName::" + local_model_name + ", parameter, flux, Nflux, energy);"

    c_function_name = "lmod" + local_model_name

    return f"""
extern "C" void {c_function_name}({parameter_list}) 
{{
    {function_call}
}} 
"""


def write_xspec_wrapper_file(outfile_name, model_names):
    file = open(outfile_name, "w")

    file.write(header)
    for model in model_names:
        file.write(get_wrapper_lmod(model))

    file.close()


if __name__ == '__main__':

    if len(sys.argv) == 3:
        input_lmodel_file = sys.argv[1]
        output_wrapper_file = sys.argv[2]

        print(f"\n *** creating {output_wrapper_file} by parsing {input_lmodel_file}:")

        list_model_names = get_model_names(input_lmodel_file)
        write_xspec_wrapper_file(output_wrapper_file, list_model_names)

    else:
        print("""
    Usage: ./create_lmod_wrapper.py [lmodel.dat] [xspec_wrapper.cpp]
        """)
        exit(1)
