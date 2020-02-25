import os

rule generate_metadata:
    input:
        stats = expand('{{assembly}}.{sra}.bam.stats', sra=list_sra_accessions(reads))
    output:
        '{assembly}.meta.yaml'
    conda:
        '../envs/py3.yaml'
    params:
        gitdir = os.path.dirname(os.path.abspath(workflow.snakefile))+'/.git'
    threads: get_threads('generate_metadata', 1)
    log:
        'logs/{assembly}/generate_metadata.log'
    benchmark:
        'logs/{assembly}/generate_metadata.benchmark.txt'
    resources:
        threads = get_threads('generate_metadata', 1)
    script:
        '../scripts/generate_metadata.py'
