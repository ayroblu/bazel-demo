use crate::types::Function;
use tree_sitter::Node;
use tree_sitter_utils::to_text;

pub(crate) fn get_function<'a>(node: &Node<'a>, source_bytes: &'a [u8]) -> Option<Function<'a>> {
    let kind = node.kind();
    if kind == "function_declaration"
        || kind == "function_expression"
        || kind == "method_definition"
    {
        // (function_declaration
        //   name: (identifier)
        //   parameters: (formal_parameters)
        //   body: (statement_block (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment))))))
        // )
        Some(Function {
            name: node
                .child_by_field_name("name")
                .map(|node| to_text(&node, source_bytes)),
            node: *node,
            body: node.child_by_field_name("body"),
            params: node.child_by_field_name("parameters"),
            return_type: node.child_by_field_name("return_type"),
        })
    } else if kind == "lexical_declaration" {
        // (lexical_declaration
        //  (variable_declarator
        //      name: (identifier)
        //      value: (arrow_function
        //          parameters: (formal_parameters)
        //          body: (statement_block
        //              (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment)))))
        //              (expression_statement (call_expression function: (member_expression object: (identifier) property: (property_identifier)) arguments: (arguments (string (string_fragment)))))
        //          )
        //      )
        //  )
        // )
        node.named_child(0)
            .filter(|node| node.kind() == "variable_declarator")
            .and_then(|node| node.child_by_field_name("value"))
            .filter(|node| node.kind() == "arrow_function")
            .map(|child_node| {
                let body = child_node.child_by_field_name("body");
                Function {
                    name: node
                        .named_child(0)
                        .and_then(|node| node.child_by_field_name("name"))
                        .map(|node| to_text(&node, source_bytes)),
                    node: *node,
                    body,
                    params: child_node.child_by_field_name("parameters"),
                    return_type: child_node.child_by_field_name("return_type"),
                }
            })
    } else if kind == "pair" {
        let name = node
            .child_by_field_name("key")
            .filter(|node| node.kind() == "property_identifier")
            .map(|node| to_text(&node, source_bytes));
        node.child_by_field_name("value").map(|child| {
            let body = child.child_by_field_name("body");
            Function {
                name,
                node: *node,
                body,
                params: child.child_by_field_name("parameters"),
                return_type: child.child_by_field_name("return_type"),
            }
        })
    } else if kind == "arrow_function" {
        node.parent()
            .filter(|node| node.kind() != "variable_declarator")
            .filter(|node| {
                node.kind() != "pair"
                    || node
                        .child_by_field_name("key")
                        .is_some_and(|node| node.kind() == "property_identifier")
            })
            .map(|_| {
                let body = node.child_by_field_name("body");
                Function {
                    name: None,
                    node: *node,
                    body,
                    params: node.child_by_field_name("parameters"),
                    return_type: node.child_by_field_name("return_type"),
                }
            })
    } else {
        None
    }
}
