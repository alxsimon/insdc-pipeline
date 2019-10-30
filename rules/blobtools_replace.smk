import os


rule make_taxid_list:
    """
    Generate a list of taxids containing all descendants of a specified root,
    optionally with one or more lineages masked.
    """
    input:
        nodes="%s/nodes.dmp" % config['settings']['taxonomy']
    output:
        '{name}.root.{root}{masked}.taxids',
        '{name}.root.{root}{masked}.negative.taxids'
    wildcard_constraints:
        root='\d+'
    params:
        mask_ids=lambda wc: similarity[wc.name]['mask_ids'],
        db=lambda wc: str("%s.root.%s%s" % (wc.name,wc.root,wc.masked))
    conda:
         '../envs/py3.yaml'
    threads: 1
    log:
      lambda wc: "logs/make_taxid_list/%s.root.%s%s.log" % (wc.name, wc.root, wc.masked)
    benchmark:
      "logs/make_taxid_list/{name}.root.{root}{masked}.benchmark.txt"
    resources:
        threads=1
    script:
        '../scripts/make_taxid_list.py'

rule make_masked_lists:
    """
    Generate a list of accessions needed to create a custom
    database containing all descendants of a specified root, optionally
    with one or more lineages masked.
    """
    input:
        split=lambda wc: "%s/split/%s.done" % (similarity[wc.name]['local'],wc.name),
        taxids='{name}.root.{root}{masked}.negative.taxids'
    output:
        'blast/{name}.root.{root}{masked}.lists'
    wildcard_constraints:
        root='\d+'
    params:
        db=lambda wc: str("%s.root.%s%s" % (wc.name,wc.root,wc.masked)),
        indir=lambda wc: "%s/split/%s" % (similarity[wc.name]['local'],wc.name),
        chunk=config['settings']['chunk']
    conda:
         '../envs/py3.yaml'
    threads: lambda x: maxcore
    log:
      lambda wc: "logs/make_masked_lists/%s.root.%s%s.log" % (wc.name, wc.root, wc.masked)
#    benchmark:
#      lambda wc: "logs/make_masked_lists/%s.root.%s%s.benchmark.txt" % (wc.name, wc.root, wc.masked)
    resources:
        threads=lambda x: maxcore
    script:
        '../scripts/make_masked_lists.py'

rule run_blastn:
    """
    Run NCBI blastn to search nucleotide database with assembly query.
    """
    input:
        fasta='{assembly}.fasta',
        db=lambda wc: "%s/%s.nal" % (similarity[wc.name]['local'],wc.name),
        taxids='{name}.root.{root}{masked}.taxids'
    output:
        out='{assembly}.blastn.{name}.root.{root}{masked}.out',
        raw='{assembly}.blastn.{name}.root.{root}{masked}.out.raw',
        nohit='{assembly}.blastn.{name}.root.{root}{masked}.nohit' if keep else temp('{assembly}.blastn.{name}.root.{root}{masked}.nohit')
    wildcard_constraints:
        root='\d+',
        masked='.[fm][ulins\d\.]+'
    params:
        db=lambda wc: "%s/%s" % (similarity[wc.name]['local'],wc.name),
        evalue=lambda wc:similarity[wc.name]['evalue'],
        max_target_seqs=lambda wc:similarity[wc.name]['max_target_seqs'],
        chunk=config['settings']['blast_chunk'],
        overlap=config['settings']['blast_overlap'],
        max_chunks=config['settings']['blast_max_chunks']
    conda:
         '../envs/pyblast.yaml'
    threads: lambda x: maxcore
    log:
      lambda wc: "logs/%s/run_blastn/%s.root.%s%s.log" % (wc.assembly, wc.name, wc.root, wc.masked)
#    benchmark:
#      "logs/{assembly}/run_blastn/{name}.root.{root}{masked}.benchmark.txt" % (wc.assembly, wc.name, wc.root, wc.masked)
    resources:
        threads=lambda x: maxcore
    script:
        '../scripts/blast_wrapper.py'


rule blobtoolkit_replace_hits:
    """
    Add ordered similarity search results to a BlobDir.
    """
    input:
        meta="%s%s/identifiers.json" % (config['assembly']['prefix'],rev),
        dbs=list_similarity_results(config),
        lineages="%s/taxidlineage.dmp" % (config['settings']['taxonomy'])
    output:
        "{assembly}%s/%s_phylum_positions.json" % (rev,config['similarity']['taxrule'])
    params:
        taxrule=config['similarity']['taxrule'] if 'taxrule' in config['similarity'] else 'bestsumorder',
        taxdump=config['settings']['taxonomy'],
        id=lambda wc: "%s%s" % (wc.assembly,rev),
        path=config['settings']['blobtools2_path'],
        dbs='.raw --hits '.join(list_similarity_results(config))
    conda:
        '../envs/blobtools2.yaml'
    threads: 1
    log:
      lambda wc: "logs/%s/blobtoolkit_replace_hits.log" % (wc.assembly)
    resources:
        threads=1,
        btk=1
    shell:
        '{params.path}/blobtools replace \
            --hits {params.dbs} \
            --taxrule "{params.taxrule}" \
            --taxdump "{params.taxdump}" \
            {params.id} > {log} 2>&1'

rule blobtoolkit_replace_cov:
    """
    Use BlobTools2 add to add coverage to a BlobDir from BAM files.
    """
    input:
        meta="%s%s/identifiers.json" % (config['assembly']['prefix'],rev),
        bam=expand("%s.{sra}.bam" % asm, sra=list_sra_accessions(reads))
    output:
        expand("%s%s/{sra}_cov.json" % (config['assembly']['prefix'],rev),sra=list_sra_accessions(reads))
    params:
        id="%s%s" % (config['assembly']['prefix'],rev),
        path=config['settings']['blobtools2_path'],
        covs=lambda wc: ' --cov '.join(["%s.%s.bam=%s" % (config['assembly']['prefix'], sra, sra) for sra in list_sra_accessions(reads)])
    conda:
        '../envs/blobtools2.yaml'
    threads: 1
    log:
      lambda wc: "logs/%s/blobtoolkit_replace_cov.log" % (config['assembly']['prefix'])
    resources:
        threads=1,
        btk=1
    shell:
        '{params.path}/blobtools replace \
            --cov {params.covs} \
            --threads {threads} \
            {params.id} > {log} 2>&1'


rule blobtoolkit_replace_busco:
    """
    import BUSCO results into BlobDir.
    """
    input:
        meta="%s%s/identifiers.json" % (config['assembly']['prefix'],rev),
        tsv=expand("%s_{lineage}.tsv" % config['assembly']['prefix'],lineage=config['busco']['lineages'])
    output:
        temp('busco.replaced'),
        expand("%s%s/{lineage}_busco.json" % (config['assembly']['prefix'],rev),lineage=config['busco']['lineages'])
    params:
        id="%s%s" % (config['assembly']['prefix'],rev),
        path=config['settings']['blobtools2_path'],
        busco=' --busco '.join(["%s_%s.tsv" % (config['assembly']['prefix'],lineage) for lineage in config['busco']['lineages']])
    conda:
        '../envs/blobtools2.yaml'
    threads: 1
    log:
      lambda wc: "logs/%s/blobtoolkit_replace_busco.log" % (config['assembly']['prefix'])
    resources:
        threads=1,
        btk=1
    shell:
        '{params.path}/blobtools replace \
            --busco {params.busco} \
            {params.id} > {log} 2>&1'
