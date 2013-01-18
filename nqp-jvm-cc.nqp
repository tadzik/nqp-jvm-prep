use QASTJASTCompiler;
use JASTNodes;
use helper;

sub MAIN(*@ARGS) {
    my $nqpcomp := pir::compreg__Ps('nqp');
    
    $nqpcomp.stages(< start parse past jast jbc jvm >);
    $nqpcomp.HOW.add_method($nqpcomp, 'jast', method ($qast, *%adverbs) {
        $qast.compilation_mode(1);
        QAST::CompilerJAST.jast($qast);
    });
    $nqpcomp.HOW.add_method($nqpcomp, 'jbc', method ($jast, *%adverbs) {
        my $dump := $jast.dump();
        spurt('QAST2JASTOutput.dump', $dump);
        my $cps := is_windows() ?? ";" !! ":";
        run('java',
            '-cp bin' ~ $cps ~ '3rdparty/bcel/bcel-5.2.jar',
            'org/perl6/nqp/jast2bc/JASTToJVMBytecode',
            'QAST2JASTOutput.dump', 'QAST2JASTOutput.class');
        'QAST2JASTOutput'
    });
    $nqpcomp.HOW.add_method($nqpcomp, 'jvm', method ($class, *%adverbs) {
        -> {
            my $cps := is_windows() ?? ";" !! ":";
            run('java',
                '-cp .' ~ $cps ~ 'bin' ~ $cps ~ '3rdparty/bcel/bcel-5.2.jar',
                'QAST2JASTOutput');
        }
    });
    
    $nqpcomp.command_line(@ARGS, :encoding('utf8'), :transcode('ascii iso-8859-1'));
}

# Set up various NQP-specific ops.
my $ops := QAST::CompilerJAST.operations();
my $RT_OBJ    := 0;
my $RT_INT    := 1;
my $RT_NUM    := 2;
my $RT_STR    := 3;
my $TYPE_TC   := 'Lorg/perl6/nqp/runtime/ThreadContext;';
my $TYPE_OPS  := 'Lorg/perl6/nqp/runtime/Ops;';
my $TYPE_SMO  := 'Lorg/perl6/nqp/sixmodel/SixModelObject;';
my $TYPE_STR  := 'Ljava/lang/String;';

$ops.add_hll_op('nqp', 'preinc', -> $qastcomp, $op {
    my $var := $op[0];
    unless nqp::istype($var, QAST::Var) {
        nqp::die("Pre-increment can only work on a variable");
    }
    $qastcomp.as_jast(QAST::Op.new(
        :op('bind'),
        $var,
        QAST::Op.new(
            :op('add_n'),
            $var,
            QAST::IVal.new( :value(1) )
        )));
});

$ops.add_hll_op('nqp', 'predec', -> $qastcomp, $op {
    my $var := $op[0];
    unless nqp::istype($var, QAST::Var) {
        nqp::die("Pre-decrement can only work on a variable");
    }
    $qastcomp.as_jast(QAST::Op.new(
        :op('bind'),
        $var,
        QAST::Op.new(
            :op('sub_n'),
            $var,
            QAST::IVal.new( :value(1) )
        )));
});

$ops.add_hll_op('nqp', 'postinc', -> $qastcomp, $op {
    my $var := $op[0];
    my $tmp := QAST::Op.unique('tmp');
    unless nqp::istype($var, QAST::Var) {
        nqp::die("Post-increment can only work on a variable");
    }
    $qastcomp.as_jast(QAST::Stmt.new(
        :resultchild(0),
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($tmp), :scope('local'), :decl('var'), :returns($var.returns) ),
            $var
        ),
        QAST::Op.new(
            :op('bind'),
            $var,
            QAST::Op.new(
                :op('add_n'),
                QAST::Var.new( :name($tmp), :scope('local'), :returns($var.returns)  ),
                QAST::IVal.new( :value(1) )
            )
        )));
});

$ops.add_hll_op('nqp', 'postdec', -> $qastcomp, $op {
    my $var := $op[0];
    my $tmp := QAST::Op.unique('tmp');
    unless nqp::istype($var, QAST::Var) {
        nqp::die("Post-decrement can only work on a variable");
    }
    $qastcomp.as_jast(QAST::Stmt.new(
        :resultchild(0),
        QAST::Op.new(
            :op('bind'),
            QAST::Var.new( :name($tmp), :scope('local'), :decl('var') ),
            $var
        ),
        QAST::Op.new(
            :op('bind'),
            $var,
            QAST::Op.new(
                :op('sub_n'),
                QAST::Var.new( :name($tmp), :scope('local') ),
                QAST::IVal.new( :value(1) )
            )
        )));
});

$ops.add_hll_op('nqp', 'numify', -> $qastcomp, $op {
    nqp::die("nqp numify op NYI");
});

$ops.add_hll_op('nqp', 'stringify', -> $qastcomp, $op {
    nqp::die("nqp stringify op NYI");
});

$ops.add_hll_op('nqp', 'falsey', -> $qastcomp, $op {
    # Compile expression to falsify.
    my $il := JAST::InstructionList.new();
    my $res := $qastcomp.as_jast($op[0]);
    $il.append($res.jast);
    $*STACK.obtain($res);
    
    # Now go by type.
    if $res.type == $RT_OBJ {
        $il.append(JAST::Instruction.new( :op('aload_1') ));
        $il.append(JAST::Instruction.new( :op('invokestatic'),
            $TYPE_OPS, 'istrue', 'Long', $TYPE_SMO, $TYPE_TC ));
    }
    elsif $res.type == $RT_STR {
        $il.append(JAST::Instruction.new( :op('aload_1') ));
        $il.append(JAST::Instruction.new( :op('invokestatic'),
            $TYPE_OPS, 'isfalse_s', 'Long', $TYPE_STR, $TYPE_TC ));
    }
    else {
        my $false := JAST::Label.new( :name($op.unique('not_false')) );
        my $done  := JAST::Label.new( :name($op.unique('not_done')) );
        $il.append(JAST::PushIVal.new( :value(0) ));
        $il.append(JAST::Instruction.new( :op($res.type == $RT_INT ?? 'lcmp' !! 'dcmpl') ));
        $il.append(JAST::Instruction.new( :op('ifne'), $false ));
        $il.append(JAST::PushIVal.new( :value(1) ));
        $il.append(JAST::Instruction.new( :op('goto'), $done ));
        $il.append($false);
        $il.append(JAST::PushIVal.new( :value(0) ));
        $il.append($done);
    }

    $qastcomp.result($il, $RT_INT)
});
