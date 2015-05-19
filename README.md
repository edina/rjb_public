# Jisc Publicatons Router

This repository contains the basics for the Router:

* The currently active importers
* The exporters to create the .zip file that's trasnferred via SWORD
* The scripts for transfering, and then looking for, records

## DEPENDENCIES

These plugins are used within an EPrints 3.2 repository.

They are dependent on three external services

* ORI

  The [Organisation and Repository Identification (ORI)](http://ori.edina.ac.uk) service provides a lookup from organisation to repositories, and is used to determine the *appropriate* repositories for a given list of organisations

* SHERPA RoMEO

  The [SHERPA RoMEO](http://www.sherpa.ac.uk/romeo/) service provides a lookup from ISSN to publisher, and is used if an ISSN is provided, but no publisher

* Organisation Identification

  The ORI lookup service requires ORI `org_ids`, so some mechanism is needed to parse the metadata supplied to identify organisations, and assign ORI `org_ids` to them

## Additional EPrints fields

The *eprint* data-type is extended to capture a quantity of additional data:

* Insert the following to the end of the list for editors, contributors, and creators:
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
