import boto3
import json

from botocore.config import Config

# Configuración para el cliente EC2
client_config = Config(region_name='us-east-1', read_timeout=890)
ec2 = boto3.client('ec2', config=client_config)

def lambda_handler(event, context):
    tag_key = 'AutoShutdown'  # Clave del tag
    tag_value = 'true'  # Valor del tag
    
    try:
        # Obtener instancias por tag
        instances = ec2.describe_instances(
            Filters=[{'Name': 'tag:' + tag_key, 'Values': [tag_value]}]
        )
        
        # Extraer los IDs y estados de las instancias a partir de la respuesta
        to_start_ids = []
        to_stop_ids = []
        for reservation in instances.get('Reservations', []):
            for instance in reservation.get('Instances', []):
                instance_id = instance['InstanceId']
                state = instance['State']['Name']
                if state == 'stopped':
                    to_start_ids.append(instance_id)
                elif state == 'running':
                    to_stop_ids.append(instance_id)
        
        # Encender las instancias apagadas
        if to_start_ids:
            start_response = ec2.start_instances(InstanceIds=to_start_ids)
            print(f'Started instances: {to_start_ids}')
        
        # Apagar las instancias encendidas
        if to_stop_ids:
            stop_response = ec2.stop_instances(InstanceIds=to_stop_ids)
            print(f'Stopped instances: {to_stop_ids}')
        
        # Formar respuesta basada en las acciones ejecutadas
        response_body = {
            'started_instances': to_start_ids,
            'stopped_instances': to_stop_ids
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body)
        }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing instances: {str(e)}')
        }
