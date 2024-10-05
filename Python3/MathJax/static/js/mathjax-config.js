window.MathJax = {
    loader: {load: ['[tex]/tagformat']},
    tex: {
        tags: 'ams',  // Step 1: Enable automatic equation numbering
        packages: {'[+]': ['tagformat']},
        tagformat: {
            number: (n) => n.toString(),
            tag: (tag) => '(' + tag + ')',
            id: (id) => 'mjx-eqn-' + id.replace(/\s/g, '_'),
            url: (id, base) => base + '#' + encodeURIComponent(id),
        }
    }
};

// Step 2: Configure the tagformat extension (optional)
MathJax.startup.ready = () => {
    MathJax.startup.defaultReady();
    MathJax.config.tex.tagformat = {
        number: (n) => n.toString(),
        tag: (tag) => '(' + tag + ')',
        id: (tag) => 'eqn-' + tag.replace(/\s/g, '_'),
        url: (id, base) => base + '#' + encodeURIComponent(id)
    };
};

// Step 3: Configure section numbering (optional)
MathJax.config.section = 1;

// Step 4: Set up filters for section numbering (optional)
MathJax.startup.ready = () => {
    MathJax.startup.defaultReady();
    MathJax.startup.input[0].preFilters.add(({math}) => {
        if (math.inputData.recompile) {
            MathJax.config.section = math.inputData.recompile.section;
        }
    });
    MathJax.startup.input[0].postFilters.add(({math}) => {
        if (math.inputData.recompile) {
            math.inputData.recompile.section = MathJax.config.section;
        }
    });
};