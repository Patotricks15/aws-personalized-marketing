"""Generates docs/architecture.drawio for the Personalized Marketing project using drawpyo.

Run with: python3 scripts/generate_diagram.py
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)


def aws_style(icon_name, fill_color):
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_group(page, name, x, y, width, height):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "rounded=0;whiteSpace=wrap;html=1;dashed=1;dashPattern=8 4;fillColor=none;"
        "strokeColor=#232F3E;verticalAlign=top;align=center;fontColor=#232F3E;fontSize=11;"
    )
    return group


def add_edge(page, source, target, label=None, bidirectional=False):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "block" if bidirectional else "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Personalized Marketing"

    group = add_group(page, "AWS Cloud", 20, 20, 900, 360)

    historical_data = add_node(page, "Historical\ninteractions data", 60, 60, "bucket", "#7AA116")
    recommendation_engine = add_node(page, "Recommendation\nengine", 60, 220, "lambda_function", "#ED7100")
    prompt_engineering = add_node(page, "Prompt\nengineering", 220, 220, "machine_learning", "#01A88D")
    foundation_models = add_node(page, "Access foundation\nmodels", 380, 220, "machine_learning", "#01A88D")
    function = add_node(page, "Function", 540, 220, "lambda_function", "#ED7100")
    send_emails = add_node(page, "Send\nemails", 700, 220, "simple_email_service", "#E7157B")
    customers = add_node(page, "Customers", 900, 220, "client", "#232F3E", width=56, height=56)

    add_edge(page, historical_data, recommendation_engine, "Data,\nmetadata")
    add_edge(page, recommendation_engine, prompt_engineering, "Output")
    add_edge(page, prompt_engineering, foundation_models, "Prompt")
    add_edge(page, foundation_models, function, "Generate\nemail")
    add_edge(page, function, send_emails, "Call API")
    add_edge(page, send_emails, customers)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
