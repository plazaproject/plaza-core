import { CompiledFlowGraph, CompiledBlock, CompiledBlockArg, ContentBlock, CompiledBlockArgList, CompiledBlockArgCallServiceDict } from '../../flow-editor/flow_graph';
const stable_stringify = require('json-stable-stringify');

type _AndOp = ['operator_and', SimpleArrayAstArgument, SimpleArrayAstArgument];
type _EqualsOp = ['operator_equals', SimpleArrayAstArgument, SimpleArrayAstArgument]
    | ['operator_equals', SimpleArrayAstArgument, SimpleArrayAstArgument, SimpleArrayAstArgument];
type _CallServiceOp = ['command_call_service',
                       { service_id: string, service_action: string, service_call_values: SimpleArrayAstArgument[] }];
type _WaitForMonitorOp = ['wait_for_monitor', { monitor_id: { from_service: string }, expected_value: any }];
type _LastValueOp = ['flow_last_value', string, number | string];
type _IfElseOp = ['control_if_else', SimpleArrayAstArgument, SimpleArrayAstOperation[]];

export type SimpleArrayAstArgument = SimpleArrayAstOperation | string | number
export type SimpleArrayAstOperation = _AndOp | _EqualsOp
    | _CallServiceOp
    | _WaitForMonitorOp | _LastValueOp
    | _IfElseOp
;

export type SimpleArrayAst = SimpleArrayAstOperation[];

function convert_argument(arg: SimpleArrayAstArgument): CompiledBlockArg {
    if ((typeof arg === 'string') || (typeof arg === 'number')) {
        return {
            type: 'constant',
            value: arg + '',
        };
    }

    return {
        type: 'block',
        value: [convert_operation(arg)],
    };
}

function convert_content_single(op: SimpleArrayAstOperation): (CompiledBlock | ContentBlock) {
    return convert_operation(op as SimpleArrayAstOperation);
}

function convert_contents(contents: SimpleArrayAstOperation[]): ContentBlock {
    return {
        contents: contents.map(v => convert_content_single(v))
    }
}

function convert_operation(op: SimpleArrayAstOperation): CompiledBlock {

    if (op[0] === 'wait_for_monitor') {
        return {
            type: op[0],
            args: op[1],
            contents: [],
        }
    }

    if (op[0] === 'command_call_service') {
        return {
            type: op[0],
            args: {
                service_action: op[1].service_action,
                service_id: op[1].service_id,
                service_call_values: op[1].service_call_values.map(v => convert_argument(v))
            },
            contents: [],
        }
    }

    if (op[0] === 'control_if_else') {
        const contents = (op.slice(2) as SimpleArrayAstOperation[][]).map(v => convert_contents(v));

        if (contents.length < 2) {
            contents.push({ contents: [] });
        }

        return {
            type: op[0],
            args: [ convert_argument(op[1]) ],
            contents: contents,
        }
    }

    const args: SimpleArrayAstArgument[] = op.slice(1);

    return {
        type: op[0],
        args: args.map(v => convert_argument(v)),
        contents: []
    }
}

export function gen_compiled(ast: SimpleArrayAst): CompiledFlowGraph {
    const result = ast.map(v => convert_operation(v));
    return result;
}

function canonicalize_arg(arg: CompiledBlockArg): CompiledBlockArg {
    if (arg.type === 'constant') {
        return arg;
    }
    else {
        return {
            type: arg.type,
            value: arg.value.map(b => canonicalize_op(b)),
        }
    }
}

function canonicalize_content(content: (CompiledBlock | ContentBlock)): (CompiledBlock | ContentBlock) {
    if ((content as CompiledBlock).type) {
        return canonicalize_op((content as CompiledBlock));
    }
    else {
        return {contents: content.contents.map(c => canonicalize_content(c))};
    }
}

function canonicalize_op(op: CompiledBlock): CompiledBlock {
    switch (op.type) {
        case "wait_for_monitor":
        case "flow_last_value":
            // Nothing to canonicalize
            break;

        case "control_if_else":
            op.args = (op.args as CompiledBlockArgList).map(arg => canonicalize_arg(arg));
            op.contents = op.contents.map(content => canonicalize_content(content));
            break;

        case "flow_set_value":
            op.args = (op.args as CompiledBlockArgList).map(arg => canonicalize_arg(arg));
            break;

        case "command_call_service":
            const values = (op.args as CompiledBlockArgCallServiceDict).service_call_values;
            if (values) {
                (op.args as CompiledBlockArgCallServiceDict).service_call_values = values.map(arg => canonicalize_arg(arg));
            }
            break;

        case "operator_and":
        case "operator_equals":
            const args = (op.args as CompiledBlockArgList).map(arg => canonicalize_arg(arg));

            // This is very inefficient, but as canonicalization only makes
            // sense on unit tests it might be acceptable
            op.args = args.sort((a, b) => stable_stringify(a).localeCompare(stable_stringify(b)));
            break;

        default:
            throw new Error(`Unknown operation: ${op.type}`);
    }

    return op;
}

function canonicalize_ast(ast: CompiledFlowGraph): CompiledFlowGraph {
    return ast.map(op => canonicalize_op(op));
}

export function canonicalize_ast_list(asts: CompiledFlowGraph[]): CompiledFlowGraph[] {
    // This sorting is very inefficient, but as canonicalization only makes
    // sense on unit tests it might be acceptable
    return asts.map(ast => canonicalize_ast(ast)).sort((a, b) => stable_stringify(a).localeCompare(stable_stringify(b)));
}
