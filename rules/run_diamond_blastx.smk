def blastx_inputs(wc):
    if 'taxrule' in config['similarity'] and config['similarity']['taxrule'].startswith('each'):
        return [
            "%s.fasta" % wc.assembly,
            "%s.root.%s%s.dmnd" % (wc.name, wc.root, wc.masked)
        ]
    return [
        "%s.blastn.%s.root.%s%s.fasta.nohit" % (wc.assembly, blast_db_name(config), wc.root, wc.masked),
        "%s.root.%s%s.dmnd" % (wc.name, wc.root, wc.masked)
    ]


rule run_diamond_blastx:
    """
    Run Diamond blastx to search protein database with assembly query.
    """
    input:
        blastx_inputs
    output:
        '{assembly}.diamond.{name}.root.{root}{masked}.out'
    wildcard_constraints:
        root = r'\d+',
        masked = r'.[fm][ulins\d\.]+',
        assembly = r'\w+'
    params:
        db = lambda wc: "%s.root.%s%s" % (wc.name, wc.root, wc.masked),
        evalue = lambda wc: similarity[wc.name]['evalue'],
        max_target_seqs = lambda wc: similarity[wc.name]['max_target_seqs']
    conda:
        '../envs/diamond.yaml'
    threads: get_threads('run_diamond_blastx', maxcore, 0.56)
    log:
        'logs/{assembly}/run_diamond_blastx/{name}.root.{root}{masked}.log'
    benchmark:
        'logs/{assembly}/run_diamond_blastx/{name}.root.{root}{masked}.benchmark.txt'
    resources:
        threads = get_threads('run_diamond_blastx', maxcore)
    shell:
        'if ! [ -s {input[0]} ]; then \
            touch {output} && exit 0; \
        fi; \
        diamond blastx \
            --query {input[0]} \
            --db {params.db} \
            --outfmt 6 qseqid staxids bitscore qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore \
            --sensitive \
            --max-target-seqs {params.max_target_seqs} \
            --evalue {params.evalue} \
            --threads {threads} \
            > {output} 2> {log}'