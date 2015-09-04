# Jisc Publicatons Router

This repository contains the basics for the Router:

* The currently active importers
* The exporters to create the .zip file that's trasnferred via SWORD
* The scripts for transfering, and then looking for, records

## DEPENDENCIES

These plugins are used within an EPrints 3.2 repository.

They are dependent on three external services

* ORI

  The [Organisation and Repository Identification (ORI)](http://ori.edina.ac.uk)
  service provides a lookup from organisation to repositories, and is used to
  determine the *appropriate* repositories for a given list of organisations

* SHERPA RoMEO

  The [SHERPA RoMEO](http://www.sherpa.ac.uk/romeo/) service provides a lookup
  from ISSN to publisher, and is used if an ISSN is provided, but no publisher

* Organisation Identification

  The ORI lookup service requires ORI `org_ids`, so some mechanism is needed
  to parse the metadata supplied to identify organisations, and assign ORI 
  `org_ids` to them.
  EDINA uses an external lexicography routine made available to the 
  University of Edinburgh to parse and identify organisations.

## Additional EPrints fields

The *eprint* data-type is extended to capture a quantity of additional data:

* Insert the following to the end of the list for editors, contributors, and 
creators:
```
    {
      'sub_name' => 'institution',
      'type' => 'text',
      'input_cols' => 20,
    },
    {
      'sub_name' => 'orgname',
      'type' => 'text',
      'input_cols' => 20,
    },
    {
      'sub_name' => 'orgid',
      'type' => 'text',
      'input_cols' => 8,
    },
    {
      'sub_name' => 'transferable',
      'type' => 'boolean',
    },
    {
      'sub_name' => 'orcid',
      'type' => 'text',
    },
```

* modify related url as below:
```
    {
      'name' => 'related_url',
      'type' => 'compound',
      'multiple' => 1,
      'fields' => [
         {
            'sub_name' => 'url',
            'type' => 'url',
            'input_cols' => 40,
          },
          {
            'sub_name' => 'format',
            'type' => 'text',
          },
          {
            'sub_name' => 'availability',
            'type' => 'text',
          },
          {
            'sub_name' => 'institution',
            'type' => 'text',
          },
      ],
      'input_boxes' => 1,
      'input_ordered' => 0,
    }
```

* and add the following to the end of the file
```
    {
      'name' => 'grants',
      'type' => 'compound',
      'multiple' => 1,
      'fields' => [
         {
           'sub_name' => 'agency',
           'type' => 'text',
           'input_cols' => 20,
         },
         {
           'sub_name' => 'grantcode',
           'type' => 'text',
           'input_cols' => 8,
         },
      ]
	  },
	  {
      'name' => 'broker',
      'type' => 'compound',
      'multiple' => 1,
      'fields' => [
         {
           'sub_name' => 'orgid',
           'type' => 'text',
         },
         {
           'sub_name' => 'orgname',
           'type' => 'text',
         },
         {
           'sub_name' => 'repoid',
           'type' => 'text',
         },
         {
           'sub_name' => 'reponame',
           'type' => 'text',
         },
         {
           'sub_name' => 'sword',
           'type' => 'boolean',
         },
         {
           'sub_name' => 'sent',
           'type' => 'time',
         },
         {
           'sub_name' => 'return',
           'type' => 'url',
         },
         {
           'sub_name' => 'live',
           'type' => 'time',
         },
         {
           'sub_name' => 'target',
           'type' => 'url',
         },
         {
           'sub_name' => 'note',
           'type' => 'text',
         },
         {
           'sub_name' => 'archiver',
           'type' => 'boolean',
         },
      ]
    },
    {
    	'name' => 'provenance',
      'type' => 'text',
    },
    {
    	'name' => 'requires_agreement',
      'type' => 'boolean',
    },
    {
    	'name' => 'openaccess',
      'type' => 'boolean',
      'input_style' => 'radio',
    },
    {
      'name' => 'doi',
      'type' => 'url',
      'render_value' => 'EPrints::Extras::render_url_truncate_end',
    },
```

## License

Copyright (c) 2015, EDINA
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
