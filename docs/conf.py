#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Tezos documentation build configuration file, created by
# sphinx-quickstart on Wed Jan 17 18:04:32 2018.
#
# This file is execfile()d with the current directory set to its
# containing dir.
#
# Note that not all possible configuration values are present in this
# autogenerated file.
#
# All configuration values have a default; values that are commented out
# serve to show the default.

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
#
# sys.path.insert(0, os.path.abspath('.'))

# We ignore the invalid-name warning that requires the global variables
# to be in UPPPER_CASE, because lower case is used by the documentation system.
# pylint: disable=invalid-name,redefined-builtin

import os
import sys
import datetime
from typing import Dict

sys.path.insert(0, os.path.abspath('.') + '/_extensions')

# -- General configuration ------------------------------------------------

# If your documentation needs a minimal Sphinx version, state it here.
#
# needs_sphinx = '1.0'

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = ['sphinx.ext.extlinks', 'tezos_custom_roles', 'michelsonlexer']

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# The suffix(es) of source filenames.
# You can specify multiple suffix as a list of string:
#
# source_suffix = ['.rst', '.md']
source_suffix = '.rst'

# The master toctree document.
master_doc = 'index'

# General information about the project.
project = 'Tezos'
copyright = '2018-2023, Nomadic Labs <contact@nomadic-labs.com>'
author = 'Nomadic Labs <contact@nomadic-labs.com>'

# The version info for the project you're documenting, acts as replacement for
# |version| and |release|, also used in various other places throughout the
# built documents.
#
# The short X.Y version.

version = os.environ.get('CI_COMMIT_REF_NAME', 'local')
# The full version, including alpha/beta/rc tags.
release = (
    '('
    + version
    + ' branch, '
    + datetime.datetime.now().strftime(" %Y/%m/%d %H:%M)")
)
# The language for content autogenerated by Sphinx. Refer to documentation
# for a list of supported languages.
#
# This is also used if you do content translation via gettext catalogs.
# Usually you set "language" from the command line for these cases.
language = None

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This patterns also effect to html_static_path and html_extra_path
exclude_patterns = [
    '.venv',
    '_build',
    'Thumbs.db',
    '.DS_Store',
    'doc_gen',
    'oxford',
]
# TODO tezos/tezos#2170: exclude the active protocol 'NNN' above

# The name of the Pygments (syntax highlighting) style to use.
pygments_style = 'sphinx'

# Deactivate syntax highlighting
# - http://www.sphinx-doc.org/en/stable/markup/code.html#code-examples
# - http://www.sphinx-doc.org/en/stable/config.html#confval-highlight_language
highlight_language = 'none'

# If true, `todo` and `todoList` produce output, else they produce nothing.
todo_include_todos = False


# -- Options for HTML output ----------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
html_theme = "sphinx_rtd_theme"

# Theme options are theme-specific and customize the look and feel of a theme
# further.  For a list of options available for each theme, see the
# documentation.
#
html_theme_options = {'logo_only': True, 'sticky_navigation': False}
html_logo = "logo.svg"
# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
html_static_path = ['_static']

html_css_files = [
    'css/custom.css',
]

html_js_files = [
    'js/custom.js',
]

html_extra_path = [
    '404.html',
    '_redirects',
    # manually copy images that are only included in raw HTML directives:
    'images/building_on_tezos_5.png',
    'images/contributing_to_octez_6.png',
    'images/discover_tezos_1.png',
    'images/getting_started_2.png',
    'images/understanding_octez_4.png',
    'images/using_octez_3.png',
]

# Custom sidebar templates, must be a dictionary that maps document names
# to template names.
#
# This is required for the alabaster theme
# refs: http://alabaster.readthedocs.io/en/latest/installation.html#sidebars
# html_sidebars = {
#     '**': [
#       'relations.html',  # needs 'show_related': True theme option to display
#       'searchbox.html',
#     ]
# }


# -- Options for HTMLHelp output ------------------------------------------

# Output file base name for HTML help builder.
htmlhelp_basename = 'Tezosdoc'


# -- Options for LaTeX output ---------------------------------------------

latex_elements: Dict[str, str] = {
    # The paper size ('letterpaper' or 'a4paper').
    #
    # 'papersize': 'letterpaper',
    # The font size ('10pt', '11pt' or '12pt').
    #
    # 'pointsize': '10pt',
    # Additional stuff for the LaTeX preamble.
    #
    # 'preamble': '',
    # Latex figure (float) alignment
    #
    # 'figure_align': 'htbp',
}

# Grouping the document tree into LaTeX files. List of tuples
# (source start file, target name, title,
#  author, documentclass [howto, manual, or own class]).
latex_documents = [
    (
        master_doc,
        'Tezos.tex',
        'Tezos Documentation',
        'Nomadic Labs \\textless{}contact@nomadic-labs.com\\textgreater{}',
        'manual',
    ),
]


# -- Options for manual page output ---------------------------------------

# One entry per manual page. List of tuples
# (source start file, name, description, authors, manual section).
man_pages = [(master_doc, 'tezos', 'Tezos Documentation', [author], 1)]


# -- Options for Texinfo output -------------------------------------------

# Grouping the document tree into Texinfo files. List of tuples
# (source start file, target name, title, author,
#  dir menu entry, description, category)
texinfo_documents = [
    (
        master_doc,
        'Tezos',
        'Tezos Documentation',
        author,
        'Tezos',
        'One line description of project.',
        'Miscellaneous',
    ),
]

# -- Ignore fragments in linkcheck

linkcheck_anchors = False
linkcheck_ignore = [
    # links which may fail for lack of access rights:
    'https://gitlab.com/nomadic-labs/tezos/-/merge_requests/',
    r'http(s)?://localhost:\d+/?',
    # local files, e.g. ../api/api-inline.html#*', \.\./CHANGES.html#version-*
    # (interpreted by linkcheck as external links, generating false positives)
    r'^\.\./',
    # flaky servers, to remove one day if they got more predictable
    r'^https://opentezos\.com/',
    r'^https://crates.io/crates/tezos-smart-rollup',
]
linkcheck_allowed_redirects = dict(
    [
        # 1. inocuous redirections (redirected with See Other / Found)
        (
            r'https://www\.sphinx-doc\.org/.*',
            r'https://www\.sphinx-doc\.org/en/master/.*',
        ),
        (
            r'https://tools\.ietf\.org/html/.*',
            r'https://datatracker\.ietf\.org/doc/.*',
        ),
        (r'https://ocaml\.org/.*', r'https://v2\.ocaml\.org/.*'),
        (
            r'https://github\.com/serokell/tezos-packaging/releases/latest',
            r'https://github\.com/serokell/tezos-packaging/releases/tag/.*',
        ),
        (
            r'https://www.reddit.com/r/tezos/',
            r'https://www.reddit.com/r/tezos/[?]rdt=[0-9]+',
        ),
        # 2. permanent redidections, maybe fix one day
        (r'https://bitheap\.org/cram/', r'https://github\.com/aiiie/cram'),
    ]
)


# Python module index generation is broken, deactivate it.
html_domain_indices = False

default_role = 'default'

html_favicon = 'favicon.ico'
